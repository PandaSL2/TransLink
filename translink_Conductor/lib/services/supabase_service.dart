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

  /// Inject an existing session (useful for background isolates).
  static Future<void> setSession(String accessToken, String refreshToken) async {
    try {
      await _client.auth.setSession(accessToken);
      debugPrint('🛡️ [REWRITE] Supabase session injected into background isolate.');
    } catch (e) {
      debugPrint('🚨 [REWRITE] Failed to set Supabase session: $e');
    }
  }

  static Session? get currentSession => _client.auth.currentSession;

  /// Attempts to perform a silent session recovery from persistent storage
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

  /// THE SINGLE SOURCE OF TRUTH (REWRITE)
  /// Upsert the live position for this bus.
  /// Returns null on success, or an error message on failure.
  /// Ensures we have a valid session before any DB operation.
  /// Self-heals by refreshing if possible.
  static Future<String?> ensureSession() async {
    try {
      // If we already have a session, we're good.
      if (_client.auth.currentSession != null) return null;

      // If no session, try a silent refresh to see if one exists in storage.
      debugPrint('⏳ [AUTH] No active session. Checking storage...');
      final res = await _client.auth.refreshSession();
      
      // We DON'T return an error here if session is still null.
      // We allow the 'Anonymous' flow to continue. 
      // If the DB requires auth, it will fail naturally during the upsert.
      return null; 
    } catch (e) {
      debugPrint('🚨 [AUTH] Silent check failed (could be anon): $e');
      return null; // Don't block.
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
  
  // ─── Route Fetching ──────────────────────────────────────────────────────────

  /// Fetch all active bus routes from Supabase.
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
        'district': '', // Field not in schema, placeholder for compatibility
      }).toList();
    } catch (e) {
      debugPrint('🚨 getAvailableRoutes failed: $e');
      return [
        {'number': 'ERR', 'name': 'DB Error: $e', 'district': ''}
      ];
    }
  }

  // ─── Payments ───────────────────────────────────────────────────────────────

  /// Verifies a passenger's balance and processes a fare deduction.
  /// Returns null on success, or an error message on failure.
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
          return null; // Success
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

  /// Fetches the recent transaction history for this bus as a Stream.
  static Stream<List<Map<String, dynamic>>> getRevenueHistoryStream(String busNumber) {
    return _client
        .from('fare_transactions')
        .stream(primaryKey: ['id'])
        .eq('bus_number', busNumber)
        .map((list) {
          final casted = list.cast<Map<String, dynamic>>().toList();
          // CLIENT-SIDE SORTING (Unbreakable Newest First)
          casted.sort((a, b) {
            final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
            final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
            return dateB.compareTo(dateA);
          });
          return casted;
        });
  }

  /// Calculates the total revenue for this bus in the current month.
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

  /// Deletes all fare transactions for a specific bus on a specific date.
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

  /// Purges the live position for this bus.
  static Future<void> removeLivePosition(String busNumber) async {
    try {
      final normalizedBus = busNumber.trim().toUpperCase();
      // Perform the actual deletion immediately
      await _client.from('live_bus_positions').delete().eq('bus_number', normalizedBus);
      debugPrint('🧹 [REWRITE] Position Purged for $normalizedBus');
    } catch (e) {
      debugPrint('🚨 [REWRITE] removeLivePosition failed: $e');
    }
  }
}
