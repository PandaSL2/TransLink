import 'dart:math';
import '../utils/geo_position.dart';
import '../constants/app_constants.dart';

class MathUtils {

  static double haversineDistance(double lat1, double lng1, double lat2, double lng2) {
    const double toRad = pi / 180.0;
    final double dLat = (lat2 - lat1) * toRad;
    final double dLng = (lng2 - lng1) * toRad;
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * toRad) * cos(lat2 * toRad) * sin(dLng / 2) * sin(dLng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return AppConstants.earthRadiusKm * c * 1000;
  }

  static GeoPosition interpolatePolyline(List<GeoPosition> polyline, double progress) {
    if (polyline.isEmpty) return const GeoPosition(79.8612, 6.9271);
    if (progress <= 0.0) return polyline.first;
    if (progress >= 1.0) return polyline.last;

    double totalDist = 0.0;
    final List<double> segLengths = [];
    for (int i = 0; i < polyline.length - 1; i++) {
      final d = haversineDistance(
        polyline[i].lat, polyline[i].lng,
        polyline[i + 1].lat, polyline[i + 1].lng,
      );
      segLengths.add(d);
      totalDist += d;
    }

    double target = totalDist * progress;
    double accumulated = 0.0;

    for (int i = 0; i < segLengths.length; i++) {
      if (accumulated + segLengths[i] >= target) {
        final double t = (target - accumulated) / segLengths[i];
        final p0 = polyline[i];
        final p1 = polyline[i + 1];
        return GeoPosition(
          p0.lng + t * (p1.lng - p0.lng),
          p0.lat + t * (p1.lat - p0.lat),
        );
      }
      accumulated += segLengths[i];
    }
    return polyline.last;
  }

  static bool isDestinationAhead(
    List<GeoPosition> polyline,
    GeoPosition userPosition,
    GeoPosition destination,
  ) {
    int userIdx = nearestPolylineIndex(polyline, userPosition);
    int destIdx = nearestPolylineIndex(polyline, destination);
    return destIdx > userIdx;
  }

  static int nearestPolylineIndex(List<GeoPosition> polyline, GeoPosition point) {
    int nearest = 0;
    double minDist = double.infinity;
    for (int i = 0; i < polyline.length; i++) {
      final d = haversineDistance(
        point.lat, point.lng,
        polyline[i].lat, polyline[i].lng,
      );
      if (d < minDist) {
        minDist = d;
        nearest = i;
      }
    }
    return nearest;
  }

  static double pointToPolylineDistance(GeoPosition point, List<GeoPosition> polyline) {
    if (polyline.isEmpty) return double.infinity;
    double minDist = double.infinity;
    for (final p in polyline) {
      final d = haversineDistance(
        point.lat, point.lng, p.lat, p.lng,
      );
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  static double calculateRouteScore({
    required double waitingMinutes,
    required double walkingMeters,
    required double durationMinutes,
    required double directnessRatio,
    required double congestionFactor,
  }) {

    final double waitScore = _normalise(waitingMinutes, 0, 30, invert: true);
    final double walkScore = _normalise(walkingMeters, 0, 800, invert: true);
    final double durationScore = _normalise(durationMinutes, 0, 120, invert: true);
    final double directnessScore = directnessRatio * 100;
    final double congestionScore = _normalise(congestionFactor, 0, 1, invert: true);

    return (AppConstants.weightWaiting * waitScore) +
        (AppConstants.weightWalking * walkScore) +
        (AppConstants.weightDuration * durationScore) +
        (AppConstants.weightDirectness * directnessScore) +
        (AppConstants.weightCongestion * congestionScore);
  }

  static double _normalise(double value, double min, double max, {bool invert = false}) {
    if (max == min) return invert ? 100 : 0;
    double norm = ((value - min) / (max - min)).clamp(0.0, 1.0) * 100;
    return invert ? 100 - norm : norm;
  }

  static List<GeoPosition> decodeEncodedPolyline(String encoded) {
    List<GeoPosition> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(GeoPosition(lng / 1E5, lat / 1E5));
    }
    return poly;
  }
}