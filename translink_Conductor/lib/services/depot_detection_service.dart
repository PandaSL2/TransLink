

import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

enum BusStatus {
  onRoute,
  atDepot,
  stopped,
  preShift,
  offRoute,
}

class _BusStand {
  final String name;
  final double lat;
  final double lng;
  final List<String> routes;

  const _BusStand(this.name, this.lat, this.lng, this.routes);
}

class DepotDetectionService {

  static const double _kDepotRadiusMetres = 450.0;

  static const double _kClusterRadiusMetres = 300.0;

  static const int _kClusterMinCount = 2;

  static const double _kStationarySpeedMs = 1.1;

  static const int _kPreShiftWindowMinutes = 40;

  static const List<_BusStand> _busStands = [

    _BusStand('Pettah Central Bus Stand',     6.9369,  79.8503, ['100','101','120','122','124','125','126','131','154']),
    _BusStand('Bastian Mawatha Bus Stand',    6.9327,  79.8501, ['2','4','6']),
    _BusStand('Olcott Mawatha Stand',         6.9352,  79.8469, ['138']),

    _BusStand('Maharagama Bus Stand',         6.8469,  79.9282, ['138']),
    _BusStand('Kottawa Bus Stand',            6.8453,  80.0027, ['129']),
    _BusStand('Homagama Bus Stand',           6.8401,  80.0044, ['129']),
    _BusStand('Pannipitiya Junction',          6.8508,  79.9516, ['129','138']),
    _BusStand('Panadura Bus Stand',           6.7132,  79.9023, ['120']),
    _BusStand('Ratmalana Bus Stand',          6.8218,  79.8832, ['131']),
    _BusStand('Moratuwa Bus Stand',           6.7734,  79.8839, ['154']),

    _BusStand('Kaduwela Bus Stand',           6.9277,  79.9926, ['124']),
    _BusStand('Kadawatha Bus Stand',          7.0131,  79.9496, ['125']),
    _BusStand('Awissawella Bus Stand',        6.9307,  80.3125, ['122']),

    _BusStand('NSBM Bus Stop',               6.8213,  80.0389, ['129']),

    _BusStand('Galle Bus Stand',             6.0329,  80.2168, ['2']),
    _BusStand('Matara Bus Stand',            5.9496,  80.5353, ['4']),
    _BusStand('Hambantota Bus Stand',        6.1246,  81.1185, ['6']),

    _BusStand('Kandy Bus Stand',             7.2906,  80.6337, ['100','K1','K2']),
    _BusStand('Peradeniya Bus Stand',        7.2675,  80.5997, ['K1']),
    _BusStand('Gampola Bus Stand',           7.1642,  80.5764, ['K2']),
  ];

  static Future<BusStatus> evaluate({
    required String routeNumber,
    required double lat,
    required double lng,
    required double speedMs,
    required String firstBus,
  }) async {

    if (_isPreShift(firstBus)) return BusStatus.preShift;

    if (_isNearDepot(routeNumber, lat, lng)) return BusStatus.atDepot;

    if (await _isClustered(routeNumber, lat, lng)) return BusStatus.atDepot;

    if (speedMs < _kStationarySpeedMs) return BusStatus.stopped;

    if (_isOffRoute(routeNumber, lat, lng)) return BusStatus.offRoute;

    return BusStatus.onRoute;
  }

  static String statusLabel(BusStatus s) => switch (s) {
    BusStatus.onRoute   => 'on_route',
    BusStatus.atDepot   => 'at_depot',
    BusStatus.stopped   => 'stopped',
    BusStatus.preShift  => 'pre_shift',
    BusStatus.offRoute  => 'off_route',
  };

  static bool _isNearDepot(String routeNumber, double lat, double lng) {
    for (final stand in _busStands) {
      if (!stand.routes.contains(routeNumber)) continue;
      final dist = _haversineMetres(lat, lng, stand.lat, stand.lng);
      if (dist <= _kDepotRadiusMetres) return true;
    }
    return false;
  }

  static Future<bool> _isClustered(String routeNumber, double lat, double lng) async {
    try {
      final client = Supabase.instance.client;

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

        if (_haversineMetres(lat, lng, rLat, rLng) < 10) continue;
        if (_haversineMetres(lat, lng, rLat, rLng) <= _kClusterRadiusMetres) {
          nearbyCount++;
        }
      }
      return nearbyCount >= _kClusterMinCount;
    } catch (_) {
      return false;
    }
  }

  static bool _isPreShift(String firstBus) {
    final parts = firstBus.split(':');
    if (parts.length < 2) return false;
    final now  = DateTime.now();
    final first = DateTime(now.year, now.month, now.day,
        int.parse(parts[0]), int.parse(parts[1]));
    return now.isBefore(first.subtract(Duration(minutes: _kPreShiftWindowMinutes)));
  }


  static bool _isOffRoute(String routeNumber, double lat, double lng) {
    final boundingBox = _routeBoundingBoxes[routeNumber];
    if (boundingBox == null) return false;

    if (lat < boundingBox.minLat || lat > boundingBox.maxLat ||
        lng < boundingBox.minLng || lng > boundingBox.maxLng) {
      return true;
    }
    return false;
  }

  static const Map<String, _BoundingBox> _routeBoundingBoxes = {

    '128': _BoundingBox(6.780, 6.855, 79.950, 80.060),

    '129': _BoundingBox(6.770, 6.855, 79.950, 80.070),

    '280': _BoundingBox(6.700, 6.870, 79.880, 80.080),

    '138': _BoundingBox(6.800, 6.950, 79.840, 79.940),
  };

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