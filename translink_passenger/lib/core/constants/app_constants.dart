class AppConstants {

  static const String supabaseUrl = 'https://utmmplibvvqscczynaug.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0bW1wbGlidnZxc2NjenluYXVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ0OTk0NTYsImV4cCI6MjA5MDA3NTQ1Nn0.FQB3UBbgcrfUPqXYi_DRKGFdUFnwe6XjicHWL76PozI';

  static const String googleMapsApiKey = 'AIzaSyAATZ7kf3YGkWbLMqkBz1aOQ-uytSe8ZlI';

  static const String holidayApiBase = 'https://date.nager.at/api/v3';
  static const String countryCode = 'LK';

  static const int busUpdateIntervalSeconds = 5;

  static const double nearbyStopRadiusMeters = 500.0;
  static const double routeProximityMeters = 500.0;

  static const double weightWaiting = 0.30;
  static const double weightWalking = 0.25;
  static const double weightDuration = 0.25;
  static const double weightDirectness = 0.10;
  static const double weightCongestion = 0.10;

  static const int delayMorningPeak = 12;
  static const int delayMidday = 5;
  static const int delayEveningPeak = 12;
  static const int delayDefault = 3;

  static const double earthRadiusKm = 6371.0;
}