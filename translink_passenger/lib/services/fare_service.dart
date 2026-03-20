
class FareService {

  static double calculateFare({
    required double distanceKm,
    bool isAC = false,
    bool isHighway = false,
  }) {
    double baseFare = 40.0;
    double perKmRate = 10.0;

    double fare = baseFare;
    if (distanceKm > 2.0) {
      fare += (distanceKm - 2.0) * perKmRate;
    }

    if (isAC) {
      fare *= 2.0;
    }

    if (isHighway) {
      fare += 150.0;
    }

    return fare.roundToDouble();
  }

  static String formatFare(double fare) {
    return 'Rs. ${fare.toStringAsFixed(0)}';
  }
}