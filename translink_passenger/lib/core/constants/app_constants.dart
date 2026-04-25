class AppConstants {
  // Supabase credentials
  static const String supabaseUrl = 'https://utmmplibvvqscczynaug.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0bW1wbGlidnZxc2NjenluYXVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ0OTk0NTYsImV4cCI6MjA5MDA3NTQ1Nn0.FQB3UBbgcrfUPqXYi_DRKGFdUFnwe6XjicHWL76PozI';

  // Google Maps API
  static const String googleMapsApiKey = 'AIzaSyAATZ7kf3YGkWbLMqkBz1aOQ-uytSe8ZlI';

  // Holiday API
  static const String holidayApiBase = 'https://date.nager.at/api/v3';
  static const String countryCode = 'LK';

  // Virtual Bus Engine
  static const int busUpdateIntervalSeconds = 5;

  // Route matching radius (metres)
  static const double nearbyStopRadiusMeters = 500.0;
  static const double routeProximityMeters = 500.0;

  // Route Scoring Weights
  static const double weightWaiting = 0.30;
  static const double weightWalking = 0.25;
  static const double weightDuration = 0.25;
  static const double weightDirectness = 0.10;
  static const double weightCongestion = 0.10;

  // Traffic delay factors (minutes)
  static const int delayMorningPeak = 12;
  static const int delayMidday = 5;
  static const int delayEveningPeak = 12;
  static const int delayDefault = 3;

  // Earth radius for Haversine
  static const double earthRadiusKm = 6371.0;
}
