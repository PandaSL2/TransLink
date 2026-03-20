import 'package:geolocator/geolocator.dart' as geo;
import '../core/utils/geo_position.dart';
import '../models/bus_models.dart';
import '../core/utils/math_utils.dart';
import '../core/constants/app_constants.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  dynamic _lastPos;

  GeoPosition? get lastPosition => _lastPos != null
    ? GeoPosition(_lastPos!.longitude, _lastPos!.latitude, heading: _lastPos!.heading)
    : null;

  Future<GeoPosition?> getCurrentLocation() async {
    const bool isWeb = identical(0, 0.0);
    if (!isWeb) {
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
    }

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) return null;
    }
    if (permission == geo.LocationPermission.deniedForever) return null;

    try {
      final geoPos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );
      _lastPos = geoPos;
      return GeoPosition(geoPos.longitude, geoPos.latitude, heading: geoPos.heading);
    } catch (_) {
      return null;
    }
  }

  Stream<GeoPosition> get locationStream => geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          distanceFilter: 20,
        ),
      ).map((p) {
        _lastPos = p;
        return GeoPosition(p.longitude, p.latitude, heading: p.heading);
      });

  List<NearbyStop> findNearbyStops(
    GeoPosition userPos,
    List<StopModel> allStops, {
    double radiusMeters = AppConstants.nearbyStopRadiusMeters,
  }) {
    final nearby = <NearbyStop>[];
    for (final stop in allStops) {
      final dist = MathUtils.haversineDistance(
        userPos.lat, userPos.lng, stop.lat, stop.lng,
      );
      if (dist <= radiusMeters) {
        nearby.add(NearbyStop(stop: stop, distanceMeters: dist));
      }
    }
    nearby.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return nearby;
  }

  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return MathUtils.haversineDistance(lat1, lng1, lat2, lng2);
  }
}

class NearbyStop {
  final StopModel stop;
  final double distanceMeters;

  const NearbyStop({required this.stop, required this.distanceMeters});

  String get distanceLabel {
    if (distanceMeters < 1000) return '${distanceMeters.round()}m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }
}