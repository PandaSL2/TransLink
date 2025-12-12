
class FareService {
  /// Official 2026 NTC Bus Fare Calculation (Sri Lanka)
  /// Base fare (Stage 1): Rs. 30.00
  /// Average increment per km: Rs. 12.00
  static double calculateFare({
    required double distanceKm,
    bool isAC = false,
    bool isHighway = false,
  }) {
    double baseFare = 40.0;
    double perKmRate = 10.0;

    // Minimum distance for base fare is typically 2.0km
    double fare = baseFare;
    if (distanceKm > 2.0) {
      fare += (distanceKm - 2.0) * perKmRate;
    }

    // AC buses are typically 2x the normal fare in 2026
    if (isAC) {
      fare *= 2.0;
    }

    // Expressway/Highway routes have fixed or higher rates
    if (isHighway) {
      fare += 150.0; // Flat highway surcharge for 2026
    }

    // Return exact calculated fare rounded to nearest rupee
    return fare.roundToDouble();
  }

  /// Formats the fare for display
  static String formatFare(double fare) {
    return 'Rs. ${fare.toStringAsFixed(0)}';
  }
}
