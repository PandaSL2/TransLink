import 'package:flutter/material.dart';
import 'package:translink_passenger/core/utils/geo_position.dart';
import '../services/fare_service.dart';

class HolidayModel {
  final DateTime holidayDate;
  final String name;
  final String? countryCode;

  HolidayModel({
    required this.holidayDate,
    required this.name,
    this.countryCode,
  });

  factory HolidayModel.fromJson(Map<String, dynamic> json) => HolidayModel(
    holidayDate: DateTime.parse(json['date'] as String),
    name: json['name'] as String? ?? json['localName'] as String? ?? 'Holiday',
    countryCode: json['countryCode'] as String?,
  );
}

class StopModel {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String? code;
  final String? address;

  StopModel({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.code,
    this.address,
  });

  factory StopModel.fromJson(Map<String, dynamic> json) => StopModel(
    id: json['id'] as String,
    name: json['name'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    code: json['code'] as String?,
    address: json['address'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lng': lng,
    'code': code,
    'address': address,
  };
}

class RouteModel {
  final String id;
  final String routeNumber;
  final String routeName;
  final String? type;
  final bool isActive;

  RouteModel({
    required this.id,
    required this.routeNumber,
    required this.routeName,
    this.type,
    this.isActive = true,
  });

  String get name => routeName;

  factory RouteModel.fromJson(Map<String, dynamic> json) => RouteModel(
    id: json['id'] as String,
    routeNumber: json['route_number'] as String,
    routeName: json['route_name'] as String? ?? 'Unnamed Route',
    type: json['type'] as String?,
    isActive: json['is_active'] as bool? ?? true,
  );
}

class RouteVariantModel {
  final String id;
  final String routeId;
  final String variantName;
  final String originName;
  final String destinationName;
  final int baseDurationMinutes;
  final bool isReturn;
  final String? polyline;

  RouteVariantModel({
    required this.id,
    required this.routeId,
    required this.variantName,
    required this.originName,
    required this.destinationName,
    required this.baseDurationMinutes,
    this.isReturn = false,
    this.polyline,
  });

  List<GeoPosition> get polylineCoords {
    if (polyline == null || polyline!.isEmpty) return [];
    return []; 
  }

  factory RouteVariantModel.fromJson(Map<String, dynamic> json) => RouteVariantModel(
    id: json['id'] as String,
    routeId: json['route_id'] as String,
    variantName: json['variant_name'] as String? ?? 'Default',
    originName: json['origin_name'] as String? ?? 'Origin',
    destinationName: json['destination_name'] as String? ?? 'Destination',
    baseDurationMinutes: json['base_duration_minutes'] as int? ?? 30,
    isReturn: json['is_return'] as bool? ?? false,
    polyline: json['polyline'] as String?,
  );
}

class RouteStopSequenceModel {
  final String id;
  final String routeVariantId;
  final String stopId;
  final int sequenceOrder;
  final int travelTimeFromOriginMinutes;
  final StopModel? stop;

  RouteStopSequenceModel({
    required this.id,
    required this.routeVariantId,
    required this.stopId,
    required this.sequenceOrder,
    this.travelTimeFromOriginMinutes = 0,
    this.stop,
  });

  factory RouteStopSequenceModel.fromJson(Map<String, dynamic> json) => RouteStopSequenceModel(
    id: json['id'] as String,
    routeVariantId: json['route_variant_id'] as String,
    stopId: json['stop_id'] as String,
    sequenceOrder: json['sequence_order'] as int? ?? 0,
    travelTimeFromOriginMinutes: json['travel_time_from_origin'] as int? ?? 0,
    stop: json['stops'] != null ? StopModel.fromJson(json['stops']) : null,
  );
}

class ServiceProfileModel {
  final String id;
  final String routeId;
  final String profileName;
  final String dayType; // weekday, weekend, holiday, all
  final String serviceType; // fixed, interval, hybrid
  final String? windowStart; // HH:mm
  final String? windowEnd;   // HH:mm
  final int? intervalMinutes;
  final int delayFactorMinutes;
  final bool isActive;

  ServiceProfileModel({
    required this.id,
    required this.routeId,
    required this.profileName,
    required this.dayType,
    required this.serviceType,
    this.windowStart,
    this.windowEnd,
    this.intervalMinutes,
    required this.delayFactorMinutes,
    this.isActive = true,
  });

  factory ServiceProfileModel.fromJson(Map<String, dynamic> json) => ServiceProfileModel(
    id: json['id'] as String,
    routeId: json['route_id'] as String,
    profileName: json['profile_name'] as String? ?? 'Standard',
    dayType: json['day_type'] as String? ?? 'all',
    serviceType: json['service_type'] as String? ?? 'fixed',
    windowStart: json['window_start'] as String?,
    windowEnd: json['window_end'] as String?,
    intervalMinutes: json['interval_minutes'] as int?,
    delayFactorMinutes: json['delay_factor_minutes'] as int? ?? 5,
    isActive: json['is_active'] as bool? ?? true,
  );
}

class NearestBusStop {
  final String name;
  final double lat;
  final double lng;
  final int walkingMeters;
  final int walkingMinutes;
  final String? placeId; 
  final String? address;
  final List<GeoPosition> walkPolyline;

  const NearestBusStop({
    required this.name,
    required this.lat,
    required this.lng,
    required this.walkingMeters,
    required this.walkingMinutes,
    this.placeId,
    this.address,
    this.walkPolyline = const [],
  });
}

class GoogleRouteResult {
  final List<BusRouteSegment> segments;
  final int totalDistanceMeters;
  final int totalDurationMinutes;
  const GoogleRouteResult({
    required this.segments,
    required this.totalDistanceMeters,
    required this.totalDurationMinutes,
  });
}

class FixedDepartureModel {
  final String id;
  final String routeVariantId;
  final String departureTime;
  final String dayType;

  FixedDepartureModel({
    required this.id,
    required this.routeVariantId,
    required this.departureTime,
    required this.dayType,
  });

  factory FixedDepartureModel.fromJson(Map<String, dynamic> json) => FixedDepartureModel(
    id: json['id'] as String,
    routeVariantId: json['route_variant_id'] as String,
    departureTime: json['departure_time'] as String,
    dayType: json['day_type'] as String? ?? 'all',
  );
}

class HolidayScheduleProfileModel {
  final String id;
  final String routeId;
  final String profileName;

  HolidayScheduleProfileModel({
    required this.id,
    required this.routeId,
    required this.profileName,
  });

  factory HolidayScheduleProfileModel.fromJson(Map<String, dynamic> json) => HolidayScheduleProfileModel(
    id: json['id'] as String,
    routeId: json['route_id'] as String,
    profileName: json['profile_name'] as String? ?? 'Holiday',
  );
}

class FavouriteModel {
  final String? id;
  final String userId;
  final String routeId;
  final String? label;
  final DateTime? createdAt;

  FavouriteModel({
    this.id,
    required this.userId,
    required this.routeId,
    this.label,
    this.createdAt,
  });

  factory FavouriteModel.fromJson(Map<String, dynamic> json) => FavouriteModel(
    id: json['id'] as String?,
    userId: json['user_id'] as String,
    routeId: json['route_id'] as String,
    label: json['label'] as String?,
    createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
  );
}

class LiveBusData {
  final String busNumber; // Unique vehicle ID (PK)
  final double lat;
  final double lng;
  final double heading;
  final double speedKmph;
  final String routeNumber;
  final String routeName;
  final DateTime lastUpdatedAt;
  final String status; // 'active', 'delayed', etc.
  final bool isActive;
  final String crowdLevel; // 'low', 'medium', 'high', 'unknown'
  final String fleetType; // 'private', 'ctb'

  LiveBusData({
    required this.busNumber,
    required this.lat,
    required this.lng,
    required this.heading,
    required this.speedKmph,
    required this.routeNumber,
    required this.routeName,
    required this.lastUpdatedAt,
    this.status = 'active',
    this.isActive = true,
    this.crowdLevel = 'unknown',
    this.fleetType = 'private',
  });

  factory LiveBusData.fromJson(Map<String, dynamic> json) => LiveBusData(
    busNumber:      json['bus_number'] ?? '',
    lat:            (json['latitude']  as num?)?.toDouble() ?? 0.0,
    lng:            (json['longitude'] as num?)?.toDouble() ?? 0.0,
    heading:        (json['heading']   as num?)?.toDouble() ?? 0.0,
    speedKmph:      ((json['speed']     as num?)?.toDouble() ?? 0.0) * 3.6,
    routeNumber:    json['route_number'] ?? '',
    routeName:      json['route_name']   ?? '',
    lastUpdatedAt: DateTime.tryParse(json['last_updated_at'] ?? '') ?? DateTime.now(),
    status:         json['status'] ?? 'active',
    isActive:       true,
    crowdLevel:     json['crowd_level'] ?? 'unknown',
    fleetType:      json['fleet_type']  ?? 'private',
  );
}

class BusLocationEstimate {
  final String nextBusAtStop;
  final int minutesAway;
  final String status;
  final double journeyProgress;
  final bool isLive;
  final double? lat;
  final double? lng;

  BusLocationEstimate({
    required this.nextBusAtStop,
    required this.minutesAway,
    required this.status,
    required this.journeyProgress,
    required this.isLive,
    this.lat,
    this.lng,
  });
}

class AiDiscoveredRoute {
  final String id;
  final String routeNumber;
  final String routeName;
  final List<String> keyStops;
  final int durationMinutes;
  final double distanceKm;
  final String firstBus;
  final String lastBus;
  final int peakFrequencyMinutes;
  final int offPeakFrequencyMinutes;
  final bool currentlyRunning;
  final String notes;
  final int? etaMinutes;
  final int score;
  final List<BusRouteSegment> segments;

  /// Dynamic Fare Estimator based on 2026 NTC bus fare rules
  double get estimatedFareLkr {
    // If the route has no bus segments (walking only), the fare is 0.
    final hasBus = segments.any((s) => s.type == SegmentType.bus);
    if (!hasBus) return 0.0;

    return FareService.calculateFare(
      distanceKm: distanceKm,
      isAC: segments.any((s) => s.routeName?.contains('AC') ?? false),
      isHighway: segments.any((s) => s.routeName?.contains('Highway') ?? false),
    );
  }

  /// Combined polyline from all segments
  List<GeoPosition> get polyline => segments.expand((s) => s.polyline).toList();

  AiDiscoveredRoute({
    required this.id,
    required this.routeNumber,
    required this.routeName,
    required this.keyStops,
    required this.durationMinutes,
    required this.distanceKm,
    required this.firstBus,
    required this.lastBus,
    required this.peakFrequencyMinutes,
    required this.offPeakFrequencyMinutes,
    required this.currentlyRunning,
    required this.notes,
    this.etaMinutes,
    required this.score,
    required this.segments,
  });

  /// The destination position: last point of the very last segment's polyline.
  GeoPosition? get destPosition {
    if (segments.isEmpty) return null;
    for (int i = segments.length - 1; i >= 0; i--) {
      if (segments[i].polyline.isNotEmpty) {
        return segments[i].polyline.last;
      }
    }
    return null;
  }

  /// Total walking distance in meters.
  int get walkingMeters => segments
      .where((s) => s.type == SegmentType.walking)
      .fold(0, (sum, s) => sum + s.distanceMeters);



  Map<String, dynamic> toJson() => {
    'id': id,
    'routeNumber': routeNumber,
    'routeName': routeName,
    'keyStops': keyStops,
    'durationMinutes': durationMinutes,
    'distanceKm': distanceKm,
    'firstBus': firstBus,
    'lastBus': lastBus,
    'peakFrequencyMinutes': peakFrequencyMinutes,
    'offPeakFrequencyMinutes': offPeakFrequencyMinutes,
    'currentlyRunning': currentlyRunning,
    'notes': notes,
    'etaMinutes': etaMinutes,
    'score': score,
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  factory AiDiscoveredRoute.fromJson(Map<String, dynamic> json) => AiDiscoveredRoute(
    id: json['id'],
    routeNumber: json['routeNumber'],
    routeName: json['routeName'],
    keyStops: List<String>.from(json['keyStops']),
    durationMinutes: json['durationMinutes'],
    distanceKm: json['distanceKm'],
    firstBus: json['firstBus'],
    lastBus: json['lastBus'],
    peakFrequencyMinutes: json['peakFrequencyMinutes'],
    offPeakFrequencyMinutes: json['offPeakFrequencyMinutes'],
    currentlyRunning: json['currentlyRunning'],
    notes: json['notes'],
    etaMinutes: json['etaMinutes'],
    score: json['score'],
    segments: (json['segments'] as List).map((s) => BusRouteSegment.fromJson(s)).toList(),
  );
}

enum SegmentType { walking, bus }

class BusRouteSegment {
  final SegmentType type;
  final String instruction;
  final int durationMin;
  final int distanceMeters;
  final List<GeoPosition> polyline;
  final String colorHex;
  final String? routeNumber;
  final String? routeName;
  final String? departureStop;
  final String? arrivalStop;
  final String? headsign;
  final int? numStops;
  final String? operator;

  BusRouteSegment({
    required this.type,
    required this.instruction,
    required this.durationMin,
    required this.distanceMeters,
    required this.polyline,
    required this.colorHex,
    this.routeNumber,
    this.routeName,
    this.departureStop,
    this.arrivalStop,
    this.headsign,
    this.numStops,
    this.operator,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'instruction': instruction,
    'durationMin': durationMin,
    'distanceMeters': distanceMeters,
    'polyline': polyline.map((p) => p.toJson()).toList(),
    'colorHex': colorHex,
    'routeNumber': routeNumber,
    'routeName': routeName,
    'departureStop': departureStop,
    'arrivalStop': arrivalStop,
    'headsign': headsign,
    'numStops': numStops,
    'operator': operator,
  };

  Color get color {
    final hex = colorHex.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    } else if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return const Color(0xFF2563EB); // Fallback blue
  }

  factory BusRouteSegment.fromJson(Map<String, dynamic> json) => BusRouteSegment(
    type: SegmentType.values.byName(json['type']),
    instruction: json['instruction'],
    durationMin: json['durationMin'],
    distanceMeters: json['distanceMeters'],
    polyline: (json['polyline'] as List).map((p) => GeoPosition.fromJson(p)).toList(),
    colorHex: json['colorHex'],
    routeNumber: json['routeNumber'],
    routeName: json['routeName'],
    departureStop: json['departureStop'],
    arrivalStop: json['arrivalStop'],
    headsign: json['headsign'],
    numStops: json['numStops'],
    operator: json['operator'],
  );
}

class VirtualBusPosition {
  final String tripId;
  final String routeVariantId;
  final String routeNumber;
  final String routeName;
  final GeoPosition position;
  final double progressRatio;
  final int etaMinutes;
  final String status;

  VirtualBusPosition({
    required this.tripId,
    required this.routeVariantId,
    required this.routeNumber,
    required this.routeName,
    required this.position,
    required this.progressRatio,
    required this.etaMinutes,
    this.status = 'on_time',
  });
}

class TripModel {
  final String? id;
  final String? destinationName;
  final double? destLat;
  final double? destLng;

  TripModel({this.id, this.destinationName, this.destLat, this.destLng});
}
