import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:translink_passenger/models/bus_models.dart';

class SupabaseService {
  static final SupabaseClient client = Supabase.instance.client;

  static Future<AuthResponse> signIn(String email, String password) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() => client.auth.signOut();

  static User? get currentUser => client.auth.currentUser;

  static Stream<AuthState> get authStateChanges =>
      client.auth.onAuthStateChange;

  static Future<List<RouteModel>> getActiveRoutes() async {
    try {
      final res = await client
          .from('routes')
          .select()
          .order('route_number');

      final list = res as List;
      return list
          .map((e) {
            final isActive = e['is_active'] as bool? ?? true;
            return RouteModel(
              id: (e['id'] ?? '').toString(),
              routeNumber: (e['route_number'] ?? '').toString(),
              routeName: (e['name'] ?? 'Unnamed Route').toString(),
              type: e['type'] as String?,
              isActive: isActive,
            );
          })
          .where((r) => r.isActive)
          .toList();
    } catch (e) {
      debugPrint('🚨 getActiveRoutes failed: $e');
      return [];
    }
  }

  static Future<List<RouteVariantModel>> getRouteVariants(String routeId) async {
    final res = await client
        .from('route_variants')
        .select()
        .eq('route_id', routeId);
    return (res as List).map((e) => RouteVariantModel.fromJson(e)).toList();
  }

  static Future<List<RouteVariantModel>> getAllRouteVariants() async {
    final res = await client.from('route_variants').select();
    return (res as List).map((e) => RouteVariantModel.fromJson(e)).toList();
  }

  static Future<List<StopModel>> getAllStops() async {
    final res = await client.from('stops').select().eq('is_active', true);
    return (res as List).map((e) => StopModel.fromJson(e)).toList();
  }

  static Future<List<RouteStopSequenceModel>> getRouteStopSequences(
      String routeVariantId) async {
    final res = await client
        .from('route_stop_sequences')
        .select('*, stops(*)')
        .eq('route_variant_id', routeVariantId)
        .order('sequence_order');
    return (res as List).map((e) => RouteStopSequenceModel.fromJson(e)).toList();
  }

  static Future<List<ServiceProfileModel>> getServiceProfiles(
      String routeId) async {
    final res = await client
        .from('service_profiles')
        .select()
        .eq('route_id', routeId)
        .eq('is_active', true);
    return (res as List).map((e) => ServiceProfileModel.fromJson(e)).toList();
  }

  static Future<List<FixedDepartureModel>> getFixedDepartures(
      String routeVariantId, String dayType) async {
    final res = await client
        .from('fixed_departures')
        .select()
        .eq('route_variant_id', routeVariantId)
        .eq('is_active', true)
        .inFilter('day_type', [dayType, 'all'])
        .order('departure_time');
    return (res as List).map((e) => FixedDepartureModel.fromJson(e)).toList();
  }


  static Future<bool> isHoliday(DateTime date) async {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final res = await client
        .from('holidays')
        .select('id')
        .eq('holiday_date', dateStr)
        .limit(1);
    return (res as List).isNotEmpty;
  }

  static Future<void> upsertHolidays(List<Map<String, dynamic>> holidays) async {
    await client.from('holidays').upsert(holidays, onConflict: 'holiday_date');
  }

  static Future<List<FavouriteModel>> getFavourites() async {
    final uid = currentUser?.id;
    if (uid == null) return [];
    final res = await client
        .from('favourites')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (res as List).map((e) => FavouriteModel.fromJson(e)).toList();
  }

  static Future<void> addFavourite(String routeId, {String? label}) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    await client
        .from('favourites')
        .upsert({'user_id': uid, 'route_id': routeId, 'label': label});
  }

  static Future<void> removeFavourite(String routeId) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    await client
        .from('favourites')
        .delete()
        .eq('user_id', uid)
        .eq('route_id', routeId);
  }

  static Future<void> updateWaitingStatus(String? routeNumber, {double? lat, double? lng}) async {
    final uid = currentUser?.id;
    if (uid == null) return;

    if (routeNumber == null) {
      await client.from('passenger_waiting').delete().eq('user_id', uid);
      return;
    }

    await client.from('passenger_waiting').upsert({
      'user_id': uid,
      'route_number': routeNumber,
      'latitude': lat,
      'longitude': lng,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  static Stream<List<LiveBusData>> getLiveBusesStream() {
    return client
        .from('live_bus_positions')
        .stream(primaryKey: ['bus_number'])
        .map((data) {
          final now = DateTime.now().toUtc();
          final buses = data
              .map((json) {
                final lastStr = json['last_updated_at'] ?? '';
                final lastUpdate = DateTime.tryParse(lastStr) ?? DateTime.now().toUtc();
                final isStale = now.difference(lastUpdate).inMinutes > 10;

                return LiveBusData(
                  busNumber: json['bus_number'] ?? '',
                  lat: (json['latitude'] as num? ?? 0.0).toDouble(),
                  lng: (json['longitude'] as num? ?? 0.0).toDouble(),
                  heading: (json['heading'] as num? ?? 0.0).toDouble(),
                  speedKmph: (json['speed'] as num? ?? 0.0).toDouble(),
                  routeNumber: json['route_number'] ?? '',
                  routeName: json['route_name'] ?? '',
                  lastUpdatedAt: lastUpdate,
                  status: json['status'] ?? 'on_time',
                  isActive: !isStale,
                  crowdLevel: 'unknown',
                  fleetType: json['fleet_type'] ?? 'private',
                );
              })
              .where((bus) => bus.isActive && bus.lat != 0.0 && bus.lng != 0.0)
              .toList();
          return buses;
        });
  }

  static Stream<double> getWalletStream() {
    final uid = currentUser?.id;
    if (uid == null) return Stream.value(0.0);
    return client
        .from('passenger_wallets')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', uid)
        .map((data) => data.isEmpty ? 0.0 : (data[0]['balance'] as num).toDouble());
  }

  static Stream<List<Map<String, dynamic>>> getTransactionsStream() {
    final uid = currentUser?.id;
    if (uid == null) return Stream.value([]);
    return client
        .from('fare_transactions')
        .stream(primaryKey: ['id'])
        .eq('passenger_id', uid)
        .map((data) {
          final list = data.cast<Map<String, dynamic>>().toList();
          list.sort((a, b) {
            final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
            final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
            return dateB.compareTo(dateA);
          });
          return list;
        });
  }

  static Future<double> getWalletBalance() async {
    final uid = currentUser?.id;
    if (uid == null) return 0.0;
    try {
      final res = await client.from('passenger_wallets').select('balance').eq('user_id', uid).maybeSingle();
      if (res == null) {
        await client.from('passenger_wallets').insert({'user_id': uid, 'balance': 500.00});
        return 500.00;
      }
      return (res['balance'] as num).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  static Future<List<Map<String, dynamic>>> getTransactions() async {
    final uid = currentUser?.id;
    if (uid == null) return [];
    try {
      final res = await client
          .from('fare_transactions')
          .select()
          .eq('passenger_id', uid)
          .order('created_at', ascending: false);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getPaymentCards() async {
    final uid = currentUser?.id;
    if (uid == null) return [];
    try {
      final res = await client.from('payment_cards').select().eq('user_id', uid);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  static Future<void> addPaymentCard(Map<String, dynamic> cardData) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    await client.from('payment_cards').insert({...cardData, 'user_id': uid});
  }

  static Future<void> deletePaymentCard(String cardId) async {
    await client.from('payment_cards').delete().eq('id', cardId);
  }

  static Future<void> topUpWallet(double amount) async {
    final uid = currentUser?.id;
    if (uid == null) return;

    try {
      final walletRes = await client.from('passenger_wallets').select('balance').eq('user_id', uid).maybeSingle();
      if (walletRes != null) {
        final double currentBalance = (walletRes['balance'] as num).toDouble();
        await client.from('passenger_wallets').update({
          'balance': currentBalance + amount,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('user_id', uid);
      } else {
        await client.from('passenger_wallets').insert({
          'user_id': uid,
          'balance': 500.0 + amount,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      await client.from('fare_transactions').insert({
        'passenger_id': uid,
        'amount': amount,
        'bus_number': 'SYSTEM',
        'route_number': 'TOPUP',
        'type': 'credit',
        'status': 'success',
        'description': 'Wallet Top-up',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Top-up failed: $e');
    }
  }

  static Future<void> updateWalletBalance(String userId, double newBalance) async {
    await client.from('passenger_wallets').update({'balance': newBalance}).eq('user_id', userId);
  }
}