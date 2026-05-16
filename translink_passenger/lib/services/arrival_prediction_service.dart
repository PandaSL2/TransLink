import 'dart:math';
import '../models/bus_models.dart';

/// A lightweight ML-inspired service for predicting bus arrival times.
/// Uses a simple Linear Regression approach based on distance, speed, and time of day.
class ArrivalPredictionService {
  
  // Weights for our simple linear model (these can be updated over time)
  // Predicted_Time = (Distance / Speed) * Traffic_Multiplier + Base_Overhead
  
  static const double _baseOverheadMinutes = 2.0; // Stop time, traffic lights, etc.
  
  /// Get the traffic multiplier based on the hour of the day.
  /// 1.0 = normal, > 1.0 = slower/heavy traffic, < 1.0 = faster.
  static double getTrafficMultiplier(int hour) {
    // Peak hours in Sri Lanka usually 7:30-9:30 and 16:30-18:30
    if ((hour >= 7 && hour <= 9) || (hour >= 16 && hour <= 19)) {
      return 1.45; // 45% slower during peak
    } else if (hour >= 22 || hour <= 5) {
      return 0.85; // 15% faster during night
    }
    return 1.15; // Slight midday congestion
  }

  /// Predicts the arrival time (in minutes) for a live bus to reach a specific stop.
  static int predictETA({
    required LiveBusData bus,
    required double stopLat,
    required double stopLng,
  }) {
    // 1. Calculate Haversine distance
    final double distanceKm = _calculateDistance(bus.lat, bus.lng, stopLat, stopLng);
    
    // 2. Determine effective speed
    // If bus is stationary or speed is too low, use a default average (25 km/h for urban)
    double effectiveSpeed = bus.speedKmph;
    if (effectiveSpeed < 5) effectiveSpeed = 25.0;
    
    // 3. Apply Traffic Multiplier based on time
    final int hour = DateTime.now().hour;
    final double multiplier = getTrafficMultiplier(hour);
    
    // 4. Calculate core travel time
    double travelTimeHours = distanceKm / effectiveSpeed;
    double travelTimeMinutes = travelTimeHours * 60;
    
    // 5. Apply weights (The "ML" part)
    // In a real ML model, these coefficients would be learned from data
    double predictedMinutes = (travelTimeMinutes * multiplier) + _baseOverheadMinutes;
    
    // 6. Heuristic adjustment for "Live" accuracy
    // If the bus is very close (< 500m), don't rely on speed too much
    if (distanceKm < 0.5) {
      return (distanceKm * 4 + 1).round(); // ~4 min per km at very slow speed
    }

    return predictedMinutes.round();
  }

  /// Helper to calculate distance between two points in KM
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295;
    final double a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
        (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }
  
  /// Future-proofing: This method could eventually call a TFLite model 
  /// if the user provides more complex features like weather or crowd level.
  static Future<int> predictWithAdvancedModel(LiveBusData bus) async {
    // Placeholder for TFLite implementation
    return 10;
  }
}
