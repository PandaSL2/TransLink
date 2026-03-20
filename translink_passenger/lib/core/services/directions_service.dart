import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:translink_passenger/core/constants/app_constants.dart';
import 'package:translink_passenger/core/utils/math_utils.dart';
import 'package:translink_passenger/models/bus_models.dart';

class DirectionsService {
  static const String _directionsUrl =
      'https://maps.googleapis.com/maps/api/directions/json';
  static const String _placesUrl =
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json';

  final String _apiKey = AppConstants.googleMapsApiKey;

  static List<NearestBusStop>? _cachedStops;
  static double? _lastCacheLat;
  static double? _lastCacheLng;

  Future<NearestBusStop?> findNearestBusStop(double userLat, double userLng) async {
    final uri = Uri.parse(
      '$_placesUrl?location=$userLat,$userLng&radius=1500&keyword=bus+stop&key=$_apiKey'
    );

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return null;

      Map<String, dynamic>? nearest;
      double nearestDist = double.infinity;
      for (final r in results) {
        final loc = r['geometry']['location'];
        final d = MathUtils.haversineDistance(
            userLat, userLng, (loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
        if (d < nearestDist) {
          nearestDist = d;
          nearest = r as Map<String, dynamic>;
        }
      }
      if (nearest == null) return null;

      final loc = nearest['geometry']['location'];
      return NearestBusStop(
        name: nearest['name'] as String? ?? 'Bus Stand',
        lat: (loc['lat'] as num).toDouble(),
        lng: (loc['lng'] as num).toDouble(),
        walkingMeters: nearestDist.toInt(),
        walkingMinutes: (nearestDist / 80).ceil(),
        placeId: nearest['place_id'] as String?,
      );
    } catch (e) {
      debugPrint('🚌 findNearestBusStop error: $e');
      return null;
    }
  }

  Future<List<NearestBusStop>> findNearbyBusStops(double userLat, double userLng) async {

    if (_cachedStops != null && _lastCacheLat != null && _lastCacheLng != null) {
      final dist = MathUtils.haversineDistance(userLat, userLng, _lastCacheLat!, _lastCacheLng!);
      if (dist < 200) {
        debugPrint('🚌 Serving nearby stops from cache (dist: ${dist.toStringAsFixed(1)}m)');
        return _cachedStops!;
      }
    }

    final uri = Uri.parse(
      '$_placesUrl?location=$userLat,$userLng&radius=2000&keyword=bus+stop&key=$_apiKey'
    );

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return _cachedStops ?? [];
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];

      final stops = <NearestBusStop>[];
      for (final r in results) {
        final loc = r['geometry']['location'];
        final d = MathUtils.haversineDistance(
            userLat, userLng, (loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
        stops.add(NearestBusStop(
          name: r['name'] as String? ?? 'Bus Stand',
          lat: (loc['lat'] as num).toDouble(),
          lng: (loc['lng'] as num).toDouble(),
          walkingMeters: d.toInt(),
          walkingMinutes: (d / 80).ceil(),
          placeId: r['place_id'] as String?,
        ));
      }

      stops.sort((a, b) => a.walkingMeters.compareTo(b.walkingMeters));
      _cachedStops = stops.take(10).toList();
      _lastCacheLat = userLat;
      _lastCacheLng = userLng;

      return _cachedStops!;
    } catch (e) {
      debugPrint('🚌 findNearbyBusStops error: $e');
      return _cachedStops ?? [];
    }
  }

  Future<List<GoogleRouteResult>> getTransitRoute(
    double originLat, double originLng,
    double destLat,   double destLng,
  ) async {
    final uri = Uri.parse(
      '$_directionsUrl'
      '?origin=$originLat,$originLng'
      '&destination=$destLat,$destLng'
      '&mode=transit'
      '&region=lk'
      '&alternatives=true'
      '&key=$_apiKey',
    );

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return [];

      final routes = data['routes'] as List;
      final results = <GoogleRouteResult>[];

      for (final route in routes) {
        final leg   = route['legs'][0] as Map<String, dynamic>;
        final steps = leg['steps'] as List<dynamic>;

        final segments = <BusRouteSegment>[];
        for (int i = 0; i < steps.length; i++) {
          final s = steps[i];
          final modeText = s['travel_mode'] as String? ?? 'WALKING';
          final isWalk   = modeText == 'WALKING';
          final pts      = s['polyline']?['points'] as String? ?? '';
          final poly     = MathUtils.decodeEncodedPolyline(pts);

          String instruction = s['html_instructions']?.toString().replaceAll(RegExp(r'<[^>]*>'), '') ?? '';

          final plusCodePattern = RegExp(r'.*?[A-Z0-9]{4,}\+[A-Z0-9]{2,}.*?', caseSensitive: false);

          if (plusCodePattern.hasMatch(instruction)) {
            final nextStep = (i + 1 < steps.length) ? steps[i + 1] : null;
            if (nextStep != null && nextStep['transit_details'] != null) {
              final stopName = nextStep['transit_details']['departure_stop']?['name'] ?? 'Bus Stop';
              instruction = 'Walk to $stopName';
            } else if (i == steps.length - 1) {
              instruction = 'Walk to Destination';
            } else {
              instruction = 'Walk to Destination';
            }
          }

          segments.add(BusRouteSegment(
            type: isWalk ? SegmentType.walking : SegmentType.bus,
            instruction: instruction,
            durationMin: (s['duration']['value'] as int) ~/ 60,
            distanceMeters: (s['distance']['value'] as int),
            polyline: poly,
            colorHex: isWalk ? 'F97316' : '2563EB',
            routeNumber: _cleanRouteNumber(s['transit_details']?['line']?['short_name'] as String?),
            routeName:   s['transit_details']?['line']?['name'] as String?,
            departureStop: s['transit_details']?['departure_stop']?['name'] as String?,
            arrivalStop:   s['transit_details']?['arrival_stop']?['name'] as String?,
            headsign: s['transit_details']?['headsign'] as String?,
            numStops: s['transit_details']?['num_stops'] as int?,
            operator: s['transit_details']?['line']?['agencies']?.first?['name'] as String?,
            departureTimeSeconds: s['transit_details']?['departure_time']?['value'] as int?,
            departureTimeText: s['transit_details']?['departure_time']?['text'] as String?,
          ));
        }

        results.add(GoogleRouteResult(
          segments: segments,
          totalDistanceMeters: leg['distance']['value'] as int? ?? 0,
          totalDurationMinutes: leg['duration']['value'] as int? ?? 0,
        ));
      }

      results.sort((a, b) {
        final aBusCount = a.segments.where((s) => s.type == SegmentType.bus).length;
        final bBusCount = b.segments.where((s) => s.type == SegmentType.bus).length;

        if (aBusCount != bBusCount) return aBusCount.compareTo(bBusCount);

        return a.totalDurationMinutes.compareTo(b.totalDurationMinutes);
      });

      return results;

    } catch (e) {
      debugPrint('🚨 getTransitRoute error: $e');
      return [];
    }
  }

  String? _cleanRouteNumber(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    final first = raw.split(' ').first;

    if (first.length > 32) return first.substring(0, 32);
    return first;
  }

  Future<AiDiscoveredRoute> buildBusRoute({
    required GoogleRouteResult transit,
    required String destLabel,
  }) async {

    final busSegments = transit.segments.where((s) => s.type == SegmentType.bus).toList();

    final List<String> gNums = busSegments.map((s) => s.routeNumber ?? 'Bus').toList();
    final List<String> cleanNums = gNums.map((n) => n.toUpperCase().trim()).toList();
    final String complexRouteNumber = cleanNums.join(' ➔ ');

    String complexRouteName = "";
    if (busSegments.length > 1) {
      final List<String> names = [];
      for (var s in busSegments) {
        if (s.headsign != null) {
          names.add(s.headsign!);
        } else if (s.routeName != null) {
          names.add(s.routeName!);
        } else {
          names.add('Bus ${s.routeNumber ?? ""}');
        }
      }
      complexRouteName = 'Transit to $destLabel (${names.join(' ➔ ')})';
    } else {
      complexRouteName = 'To $destLabel';
    }

    final totalSegTime = transit.segments.fold(0, (sum, seg) => sum + seg.durationMin);
    final busCount = busSegments.length;

    final totalDuration = totalSegTime + (busCount * 5);

    return AiDiscoveredRoute(
      id: 'google_${cleanNums.join('_')}_${DateTime.now().microsecondsSinceEpoch}',
      routeNumber: complexRouteNumber,
      routeName: complexRouteName,
      keyStops: busSegments
          .map((s) => s.arrivalStop)
          .where((s) => s != null)
          .cast<String>()
          .toList(),
      durationMinutes: totalDuration,
      distanceKm: transit.totalDistanceMeters / 1000.0,
      firstBus: 'Scheduled',
      lastBus: 'Scheduled',
      peakFrequencyMinutes: 15,
      offPeakFrequencyMinutes: 30,
      currentlyRunning: true,
      notes: busSegments.length > 1
          ? 'Multi-Bus Transit'
          : (transit.segments.any((s) => s.type == SegmentType.walking) ? 'Includes walking' : 'Direct bus'),
      score: 100,
      segments: transit.segments,
    );
  }
}