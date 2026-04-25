
class TrainRoute {
  final String id;
  final String lineName;
  final String trainType; // 'Express', 'Slow', 'Intercity'
  final String fromStation;
  final String toStation;
  final List<String> departureTimes;
  final double distanceKm;

  TrainRoute({
    required this.id,
    required this.lineName,
    required this.trainType,
    required this.fromStation,
    required this.toStation,
    required this.departureTimes,
    required this.distanceKm,
  });
}

class InterchangeService {
  /// Mock dataset of major Sri Lankan train lines for 2026 integration
  static final List<TrainRoute> _slrSchedules = [
    TrainRoute(
      id: 't1',
      lineName: 'Main Line',
      trainType: 'Express',
      fromStation: 'Colombo Fort',
      toStation: 'Gampaha',
      departureTimes: ['06:10', '07:30', '16:45', '17:20'],
      distanceKm: 28.5,
    ),
    TrainRoute(
      id: 't2',
      lineName: 'Coastal Line',
      trainType: 'Intercity',
      fromStation: 'Colombo Fort',
      toStation: 'Panadura',
      departureTimes: ['06:50', '08:15', '17:10', '18:05'],
      distanceKm: 26.0,
    ),
    TrainRoute(
      id: 't3',
      lineName: 'Coastal Line',
      trainType: 'Express',
      fromStation: 'Colombo Fort',
      toStation: 'Galle',
      departureTimes: ['06:30', '07:00', '15:30', '17:30'],
      distanceKm: 115.0,
    ),
  ];

  /// Find a train interchange for a given destination
  static TrainRoute? findTrainInterchange(String destination) {
    final destLower = destination.toLowerCase();
    if (destLower.contains('gampaha')) return _slrSchedules[0];
    if (destLower.contains('panadura')) return _slrSchedules[1];
    if (destLower.contains('galle')) return _slrSchedules[2];
    return null;
  }

  /// Create a multi-modal route suggestion involving a train
  static String getInterchangeInstruction(TrainRoute train) {
    return 'Take ${train.trainType} train (${train.lineName}) from ${train.fromStation}. Next departures: ${train.departureTimes.join(", ")}';
  }
}
