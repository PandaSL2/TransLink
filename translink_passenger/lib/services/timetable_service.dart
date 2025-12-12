import '../models/bus_models.dart';

class TimetableService {
  // ─────────────────────────────────────────────────────────
  // Generate all departure DateTimes for a given date
  // across all service profiles for a route variant
  // ─────────────────────────────────────────────────────────
  static List<DateTime> generateDepartureTimes({
    required List<ServiceProfileModel> profiles,
    required List<FixedDepartureModel> fixedDepartures,
    required DateTime date,
  }) {
    final times = <DateTime>{};

    for (final profile in profiles) {
      if (profile.serviceType == 'fixed') {
        // Fixed: use fixed_departures table
        for (final f in fixedDepartures) {
          final t = _parseTime(f.departureTime, date);
          if (t != null) times.add(t);
        }
      } else if (profile.serviceType == 'interval' ||
          profile.serviceType == 'hybrid') {
        // Interval / Hybrid: generate from window + interval
        if (profile.windowStart != null &&
            profile.windowEnd != null &&
            profile.intervalMinutes != null) {
          final windowTimes = _generateInterval(
            date: date,
            windowStart: profile.windowStart!,
            windowEnd: profile.windowEnd!,
            intervalMinutes: profile.intervalMinutes!,
          );
          times.addAll(windowTimes);
        }
      }
    }

    final sorted = times.toList()..sort();
    return sorted;
  }

  // ─────────────────────────────────────────────────────────
  // Get next N departure times from now
  // ─────────────────────────────────────────────────────────
  static List<DateTime> getUpcoming({
    required List<DateTime> allDepartures,
    int count = 5,
    DateTime? from,
  }) {
    final now = from ?? DateTime.now();
    return allDepartures
        .where((t) => t.isAfter(now))
        .take(count)
        .toList();
  }

  // ─────────────────────────────────────────────────────────
  // ETA for a specific stop index along a route variant
  // ─────────────────────────────────────────────────────────
  static int etaForStop({
    required DateTime departureTime,
    required int travelTimeFromOriginMinutes,
    required int delayFactorMinutes,
  }) {
    final arrivalTime = departureTime.add(
      Duration(minutes: travelTimeFromOriginMinutes + delayFactorMinutes),
    );
    return arrivalTime.difference(DateTime.now()).inMinutes;
  }

  // ─────────────────────────────────────────────────────────
  // Day type helper
  // ─────────────────────────────────────────────────────────
  static String getDayType(DateTime date, {bool isHoliday = false}) {
    if (isHoliday) return 'holiday';
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return 'weekend';
    }
    return 'weekday';
  }

  // ─────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────
  static List<DateTime> _generateInterval({
    required DateTime date,
    required String windowStart,
    required String windowEnd,
    required int intervalMinutes,
  }) {
    final start = _parseTime(windowStart, date);
    final end = _parseTime(windowEnd, date);
    if (start == null || end == null) return [];

    final times = <DateTime>[];
    DateTime current = start;
    while (!current.isAfter(end)) {
      times.add(current);
      current = current.add(Duration(minutes: intervalMinutes));
    }
    return times;
  }

  static DateTime? _parseTime(String timeStr, DateTime date) {
    // timeStr format: "HH:mm" or "HH:mm:ss"
    final parts = timeStr.split(':');
    if (parts.length < 2) return null;
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
    );
  }
}
