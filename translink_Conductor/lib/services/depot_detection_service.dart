// ─────────────────────────────────────────────────────────────────────────────
// Depot Detection Service
//
// Determines whether a bus is genuinely ON ITS ROUTE or just:
//   A) Parked at a bus stand / depot (pre-departure)
//   B) Travelling from the driver's home to the start point
//   C) Clustered with other buses at a terminus
//
// Three combined signals → a single BusStatus enum:
//   - Signal A: GPS within 400 m of a known bus stand for this route
//   - Signal B: 2+ other Driver-App devices on same route within 300 m (Supabase query)
//   - Signal C: Speed < 4 km/h continuously (bus is stationary)
//
// Sri Lankan context:
//   Buses congregate at fixed terminus points before departure.
//   Once they depart (move > 400 m from depot at > 10 km/h) they are live on route.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

enum BusStatus {
  onRoute,    // ✅ Live — show on passenger map with LIVE badge
  atDepot,    // 🚌 At bus stand — show as "At Bus Stand" (not live position)
  stopped,    // ⏸ Temporary stop (traffic/passenger pickup)
  preShift,   // 🕐 Too early — bus not yet in service window
  offRoute,   // ⛽ Diverted (e.g., getting fuel) — hide from passengers
}

// ─────────────────────────────────────────────────────────────────────────────
// Known Sri Lankan bus stand / terminus coordinates.
// Keys = route numbers that START from that stand.
// ─────────────────────────────────────────────────────────────────────────────
class _BusStand {
  final String name;
  final double lat;
  final double lng;
  final List<String> routes; // route numbers starting/ending here

  const _BusStand(this.name, this.lat, this.lng, this.routes);
}

class DepotDetectionService {
  /// Radius within which a bus is considered "at the depot" (metres).
  static const double _kDepotRadiusMetres = 450.0;

  /// Radius for cluster detection (metres).
  static const double _kClusterRadiusMetres = 300.0;

  /// Minimum other buses to form a cluster.
  static const int _kClusterMinCount = 2;

  /// Speed below which a bus is considered stationary (m/s ≈ 4 km/h).
  static const double _kStationarySpeedMs = 1.1;

  /// How many minutes before first_bus the driver may be at the stand.
  static const int _kPreShiftWindowMinutes = 40;

  // Build at compile-time — no allocations at runtime.
  static const List<_BusStand> _busStands = [
    // Colombo Central
    _BusStand('Pettah Central Bus Stand',     6.9369,  79.8503, ['100','101','120','122','124','125','126','131','154']),
    _BusStand('Bastian Mawatha Bus Stand',    6.9327,  79.8501, ['2','4','6']),
    _BusStand('Olcott Mawatha Stand',         6.9352,  79.8469, ['138']),

    // South
    _BusStand('Maharagama Bus Stand',         6.8469,  79.9282, ['138']),
    _BusStand('Kottawa Bus Stand',            6.8453,  80.0027, ['129']),
    _BusStand('Homagama Bus Stand',           6.8401,  80.0044, ['129']),
    _BusStand('Pannipitiya Junction',          6.8508,  79.9516, ['129','138']),
    _BusStand('Panadura Bus Stand',           6.7132,  79.9023, ['120']),
    _BusStand('Ratmalana Bus Stand',          6.8218,  79.8832, ['131']),
    _BusStand('Moratuwa Bus Stand',           6.7734,  79.8839, ['154']),

    // East/Inland
    _BusStand('Kaduwela Bus Stand',           6.9277,  79.9926, ['124']),
    _BusStand('Kadawatha Bus Stand',          7.0131,  79.9496, ['125']),
    _BusStand('Awissawella Bus Stand',        6.9307,  80.3125, ['122']),

    // North Suburbs
    _BusStand('NSBM Bus Stop',               6.8213,  80.0389, ['129']),

    // Galle / South
    _BusStand('Galle Bus Stand',             6.0329,  80.2168, ['2']),
    _BusStand('Matara Bus Stand',            5.9496,  80.5353, ['4']),
    _BusStand('Hambantota Bus Stand',        6.1246,  81.1185, ['6']),

    // Kandy
    _BusStand('Kandy Bus Stand',             7.2906,  80.6337, ['100','K1','K2']),
    _BusStand('Peradeniya Bus Stand',        7.2675,  80.5997, ['K1']),
    _BusStand('Gampola Bus Stand',           7.1642,  80.5764, ['K2']),
  ];

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Full depot/status evaluation combining all three signals.
  /// [speed] is in m/s (from Geolocator).
  static Future<BusStatus> evaluate({
    required String routeNumber,
    required double lat,
    required double lng,
    required double speedMs,
    required String firstBus, // "HH:MM"
  }) async {
    // Signal: pre-shift (too early even for depot boarding)
    if (_isPreShift(firstBus)) return BusStatus.preShift;

    // Signal A: proximity to known bus stand
    if (_isNearDepot(routeNumber, lat, lng)) return BusStatus.atDepot;

    // Signal B: cluster of other buses on same route nearby (Supabase)
    if (await _isClustered(routeNumber, lat, lng)) return BusStatus.atDepot;

    // Signal C: stationary
    if (speedMs < _kStationarySpeedMs) return BusStatus.stopped;

    // Signal D: off-route deviation (e.g. for fuel) >= 1.5km
    if (_isOffRoute(routeNumber, lat, lng)) return BusStatus.offRoute;

    return BusStatus.onRoute;
  }

  /// Convert BusStatus to a short Supabase status string.
  static String statusLabel(BusStatus s) => switch (s) {
    BusStatus.onRoute   => 'on_route',
    BusStatus.atDepot   => 'at_depot',
    BusStatus.stopped   => 'stopped',
    BusStatus.preShift  => 'pre_shift',
    BusStatus.offRoute  => 'off_route',
  };

  // ─── Signal A: known depot proximity ────────────────────────────────────────

  static bool _isNearDepot(String routeNumber, double lat, double lng) {
    for (final stand in _busStands) {
      if (!stand.routes.contains(routeNumber)) continue;
      final dist = _haversineMetres(lat, lng, stand.lat, stand.lng);
      if (dist <= _kDepotRadiusMetres) return true;
    }
    return false;
  }

  // ─── Signal B: cluster detection via Supabase ───────────────────────────────

  static Future<bool> _isClustered(String routeNumber, double lat, double lng) async {
    try {
      final client = Supabase.instance.client;
      // Fetch all OTHER buses on the same route that updated in the last 5 min.
      final rows = await client
          .from('live_bus_positions')
          .select('latitude,longitude')
          .eq('route_number', routeNumber)
          .gte('last_updated_at',
              DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String());

      int nearbyCount = 0;
      for (final row in rows) {
        final rLat = (row['latitude'] as num).toDouble();
        final rLng = (row['longitude'] as num).toDouble();
        // Skip self (same location)
        if (_haversineMetres(lat, lng, rLat, rLng) < 10) continue;
        if (_haversineMetres(lat, lng, rLat, rLng) <= _kClusterRadiusMetres) {
          nearbyCount++;
        }
      }
      return nearbyCount >= _kClusterMinCount;
    } catch (_) {
      return false; // Network error → don't suppress
    }
  }

  // ─── Signal: pre-shift ──────────────────────────────────────────────────────

  static bool _isPreShift(String firstBus) {
    final parts = firstBus.split(':');
    if (parts.length < 2) return false;
    final now  = DateTime.now();
    final first = DateTime(now.year, now.month, now.day,
        int.parse(parts[0]), int.parse(parts[1]));
    return now.isBefore(first.subtract(Duration(minutes: _kPreShiftWindowMinutes)));
  }

  // ─── Signal D: Off-Route Detection (Geofencing) ───────────────────────────
  // If a bus deviates > 1.5km from its known path (e.g., going to a petrol shed)
  // we temporarily mark it as offRoute so it disappears from the passenger map.
  
  static const double _kMaxRouteDeviationMetres = 1500.0;

  static bool _isOffRoute(String routeNumber, double lat, double lng) {
    final boundingBox = _routeBoundingBoxes[routeNumber];
    if (boundingBox == null) return false; // Route untracked, assume on route
    
    // Check if outside the broad rectangular bounding box around the whole route.
    // If it is, the bus has definitely abandoned the physical region of the route.
    if (lat < boundingBox.minLat || lat > boundingBox.maxLat || 
        lng < boundingBox.minLng || lng > boundingBox.maxLng) {
      return true;
    }
    return false;
  }

  // Very rough bounding boxes (MinLat, MaxLat, MinLng, MaxLng) for major routes.
  // We expand the boxes by ~1.5km (approx 0.015 degrees) to allow for minor detours/traffic.
  static const Map<String, _BoundingBox> _routeBoundingBoxes = {
    // 128: Kottawa to Thalagala
    '128': _BoundingBox(6.780, 6.855, 79.950, 80.060),
    // 129: Kottawa to Moragahahena
    '129': _BoundingBox(6.770, 6.855, 79.950, 80.070),
    // 280: Maharagama to Horana
    '280': _BoundingBox(6.700, 6.870, 79.880, 80.080),
    // 138: Maharagama to Colombo Fort
    '138': _BoundingBox(6.800, 6.950, 79.840, 79.940),
  };

  // ─── Haversine distance (metres) ────────────────────────────────────────────

  static double _haversineMetres(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}

class _BoundingBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  const _BoundingBox(this.minLat, this.maxLat, this.minLng, this.maxLng);
}
