/// Lightweight coordinate class replacing the Mapbox `Position` type.
/// Constructor: GeoPosition(lng, lat) — matches Mapbox convention.
class GeoPosition {
  final double lng;
  final double lat;
  final double? heading;

  const GeoPosition(this.lng, this.lat, {this.heading});

  factory GeoPosition.fromJson(Map<String, dynamic> json) => GeoPosition(
    (json['lng'] as num).toDouble(),
    (json['lat'] as num).toDouble(),
    heading: (json['heading'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'lng': lng,
    'lat': lat,
    if (heading != null) 'heading': heading,
  };

  @override
  String toString() => 'GeoPosition(lng: $lng, lat: $lat, heading: $heading)';

  @override
  bool operator ==(Object other) =>
      other is GeoPosition && other.lng == lng && other.lat == lat && other.heading == heading;

  @override
  int get hashCode => Object.hash(lng, lat, heading);
}
