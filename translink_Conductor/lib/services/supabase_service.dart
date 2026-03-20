import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/driver_constants.dart';

class SupabaseService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: DriverConstants.supabaseUrl,
      anonKey: DriverConstants.supabaseAnonKey,
    );
  }

  static Future<void> setSession(String accessToken, String refreshToken) async {
    try {
      await _client.auth.setSession(accessToken);
      debugPrint('🛡️ [REWRITE] Supabase session injected into background isolate.');
    } catch (e) {
      debugPrint('🚨 [REWRITE] Failed to set Supabase session: $e');
    }
  }

  static Session? get currentSession => _client.auth.currentSession;

  static Future<bool> recoverSession() async {
    try {
      debugPrint('⏳ [AUTH-RECOVERY] Attempting silent session recovery...');
      final response = await _client.auth.refreshSession();
      if (response.session != null) {
        debugPrint('✅ [AUTH-RECOVERY] Session restored: ${response.session!.user.id}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('🚨 [AUTH-RECOVERY] Recovery failed: $e');
      return false;
    }
  }

  static Future<String?> ensureSession() async {
    try {

      if (_client.auth.currentSession != null) return null;

      debugPrint('⏳ [AUTH] No active session. Checking storage...');
      await _client.auth.refreshSession();

      return null;
    } catch (e) {
      debugPrint('🚨 [AUTH] Silent check failed (could be anon): $e');
      return null;
    }
  }

  static Future<String?> updateLivePosition({
    required String busNumber,
    required String routeNumber,
    required String routeName,
    required double lat,
    required double lng,
    double speed = 0,
    double heading = 0,
    String status = 'on_time',
    int headwayMinutes = 20,
    DateTime? nextBusDueAt,
    String fleetType = 'private',
  }) async {
    try {
      final normalizedBus = busNumber.trim().toUpperCase();

      await _client.from('live_bus_positions').upsert({
        'bus_number':      normalizedBus,
        'route_number':    routeNumber,
        'route_name':      routeName,
        'latitude':        lat,
        'longitude':       lng,
        'speed':           speed,
        'heading':         heading,
        'status':          status,
        'fleet_type':      fleetType,
        'last_updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'bus_number');

      debugPrint('📡 [RECOVERY] Broadcast Success for $busNumber');
      return null;
    } catch (e) {
      String errMsg = 'Database Sync Failed';
      if (e is PostgrestException) {
        errMsg = 'DB Error ${e.code}: ${e.message}';
        if (e.code == '42501') {
          errMsg = 'Permission Denied: Another driver may be using this bus number.';
        }
        debugPrint('🚨 [RECOVERY] PostgrestException: ${e.code} - ${e.message}');
      } else {
        errMsg = e.toString();
        debugPrint('🚨 [RECOVERY] updateLivePosition failed: $e');
      }
      return errMsg;
    }
  }

  static Future<void> signOut() => _client.auth.signOut();

  static User? get currentUser => _client.auth.currentUser;

  static Future<List<Map<String, String>>> getAvailableRoutes() async {
    try {
      final response = await _client
          .from('routes')
          .select('route_number, name')
          .eq('is_active', true);

      final list = response as List;
      return list.map((e) => {
        'number': (e['route_number'] ?? 'Unknown').toString(),
        'name': (e['name'] ?? 'Unnamed Route').toString(),
        'district': '',
      }).toList();
    } catch (e) {
      debugPrint('🚨 getAvailableRoutes failed: $e');
      return [
        {'number': 'ERR', 'name': 'DB Error: $e', 'district': ''}
      ];
    }
  }

  static Future<String?> processPayment({
    String? passengerId,
    required double amount,
    required String busNumber,
    required String routeNumber,
    String? startStop,
    String? endStop,
  }) async {
    try {
      final res = await _client.rpc('handle_payment', params: {
        'p_passenger_id': passengerId,
        'p_amount':       amount,
        'p_bus_number':   busNumber,
        'p_route_number': routeNumber,
        'p_start_stop':   startStop ?? 'Unknown Stop',
        'p_end_stop':     endStop ?? 'Route Destination',
      });

      if (res != null && res is Map) {
        if (res['success'] == true) {
          return null;
        } else {
          return res['error'] ?? "Payment failed.";
        }
      }
      return "Invalid server response.";
    } catch (e) {
      debugPrint('🚨 processPayment RPC error: $e');
      return "Payment processing failed: $e";
    }
  }

  static Stream<List<Map<String, dynamic>>> getRevenueHistoryStream(String busNumber) {
    return _client
        .from('fare_transactions')
        .stream(primaryKey: ['id'])
        .eq('bus_number', busNumber)
        .map((list) {
          final casted = list.cast<Map<String, dynamic>>().toList();

          casted.sort((a, b) {
            final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
            final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
            return dateB.compareTo(dateA);
          });
          return casted;
        });
  }

  static Future<double> getMonthRevenue(String busNumber) async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1).toUtc().toIso8601String();

      final res = await _client
          .from('fare_transactions')
          .select('amount')
          .eq('bus_number', busNumber)
          .gte('created_at', startOfMonth);

      final list = res as List;
      double total = 0;
      for (var row in list) {
        total += (row['amount'] as num).toDouble();
      }
      return total;
    } catch (e) {
      debugPrint('🚨 getMonthRevenue error: $e');
      return 0.0;
    }
  }

  static Future<void> deleteDayRevenue(String busNumber, DateTime date) async {
    try {
      final start = DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
      final end = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).toUtc().toIso8601String();
      await _client
          .from('fare_transactions')
          .delete()
          .eq('bus_number', busNumber)
          .gte('created_at', start)
          .lte('created_at', end);
    } catch (e) {
      debugPrint('🚨 deleteDayRevenue error: $e');
    }
  }

  static Future<void> removeLivePosition(String busNumber) async {
    try {
      final normalizedBus = busNumber.trim().toUpperCase();

      await _client.from('live_bus_positions').delete().eq('bus_number', normalizedBus);
      debugPrint('🧹 [REWRITE] Position Purged for $normalizedBus');
    } catch (e) {
      debugPrint('🚨 [REWRITE] removeLivePosition failed: $e');
    }
  }
}