// Route Schedule Service
// Local, offline-first schedule database for Sri Lankan bus routes.
// Provides headway (frequency), operating hours, and next-bus calculations.
// No network calls required — deterministic and instant.

class RouteSchedule {
  final int headwayMinutes; // How often busses run on this route
  final String firstBus;    // "HH:MM" 24-hour format
  final String lastBus;     // "HH:MM" 24-hour format
  final String label;       // Human-readable label

  const RouteSchedule({
    required this.headwayMinutes,
    required this.firstBus,
    required this.lastBus,
    required this.label,
  });

  factory RouteSchedule.fromJson(Map<String, dynamic> json) {
    return RouteSchedule(
      headwayMinutes: json['headway_minutes'] as int? ?? 20,
      firstBus: json['first_bus'] as String? ?? '05:30',
      lastBus: json['last_bus'] as String? ?? '21:00',
      label: json['route_name'] as String? ?? 'General Route',
    );
  }

  String get frequencyLabel => 'Every $headwayMinutes min';
  String get hoursLabel => '$firstBus – $lastBus';
}

class RouteScheduleService {
  // -----------------------------------------------------------------------
  // Schedule database — add more routes here as needed.
  // headwayMinutes: average minutes between buses on this route.
  // firstBus / lastBus: operating window (24-hour, Sri Lanka local time).
  // -----------------------------------------------------------------------
  static const Map<String, RouteSchedule> _schedules = {
    // ── Homagama Corridor (private routes) ───────────────────────────────────
    '128': RouteSchedule(headwayMinutes: 15, firstBus: '05:30', lastBus: '21:00', label: 'Kottawa – Thalagala via Homagama'),
    '129': RouteSchedule(headwayMinutes: 12, firstBus: '05:30', lastBus: '21:30', label: 'Kottawa – Moragahahena via Homagama'),
    '280': RouteSchedule(headwayMinutes: 20, firstBus: '05:30', lastBus: '21:00', label: 'Maharagama – Horana'),

    // ── Colombo Metro ────────────────────────────────────────────────────────
    '100': RouteSchedule(headwayMinutes: 8,  firstBus: '05:00', lastBus: '22:30', label: 'Colombo – Kandy'),
    '101': RouteSchedule(headwayMinutes: 10, firstBus: '05:00', lastBus: '22:00', label: 'Colombo – Negombo'),
    '120': RouteSchedule(headwayMinutes: 10, firstBus: '05:30', lastBus: '21:30', label: 'Colombo – Panadura'),
    '122': RouteSchedule(headwayMinutes: 20, firstBus: '05:30', lastBus: '21:00', label: 'Awissawella – Colombo'),
    '124': RouteSchedule(headwayMinutes: 15, firstBus: '05:00', lastBus: '22:00', label: 'Colombo – Kaduwela'),
    '125': RouteSchedule(headwayMinutes: 12, firstBus: '05:30', lastBus: '22:00', label: 'Colombo – Kadawatha'),
    '126': RouteSchedule(headwayMinutes: 10, firstBus: '05:00', lastBus: '22:30', label: 'Borella – Ampara'),
    '131': RouteSchedule(headwayMinutes: 15, firstBus: '05:30', lastBus: '21:30', label: 'Colombo – Ratmalana'),
    '138': RouteSchedule(headwayMinutes: 15, firstBus: '05:00', lastBus: '21:30', label: 'Maharagama – Colombo'),
    '154': RouteSchedule(headwayMinutes: 20, firstBus: '05:30', lastBus: '21:00', label: 'Colombo – Moratuwa'),

    // ── Outer Routes ────────────────────────────────────────────────────────
    '2':   RouteSchedule(headwayMinutes: 30, firstBus: '06:00', lastBus: '19:00', label: 'Colombo – Galle'),
    '4':   RouteSchedule(headwayMinutes: 25, firstBus: '06:00', lastBus: '19:30', label: 'Colombo – Matara'),
    '6':   RouteSchedule(headwayMinutes: 30, firstBus: '06:00', lastBus: '18:00', label: 'Colombo – Hambantota'),
    'K1':  RouteSchedule(headwayMinutes: 20, firstBus: '05:30', lastBus: '21:00', label: 'Kandy – Peradeniya'),
    'K2':  RouteSchedule(headwayMinutes: 25, firstBus: '06:00', lastBus: '20:00', label: 'Kandy – Gampola'),
  };

  /// Default fallback schedule for unknown routes.
  static const RouteSchedule _defaultSchedule = RouteSchedule(
    headwayMinutes: 20,
    firstBus: '05:30',
    lastBus: '21:00',
    label: 'General Route',
  );

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Get the schedule for a route number. Returns a sensible default if unknown.
  static RouteSchedule getSchedule(String routeNumber) {
    return _schedules[routeNumber.trim()] ?? _defaultSchedule;
  }

  static bool isWithinOperatingHours(String routeNumber) {
    final schedule = getSchedule(routeNumber);
    final now = DateTime.now();
    final first = _parseTime(schedule.firstBus, now);
    final last  = _parseTime(schedule.lastBus, now);
    return now.isAfter(first) && now.isBefore(last);
  }

  /// Compute when the next bus is due (now + headway) for the given route.
  static DateTime computeNextBusDue(String routeNumber) {
    final schedule = getSchedule(routeNumber);
    return DateTime.now().add(Duration(minutes: schedule.headwayMinutes));
  }

  static int minutesUntilLastBus(String routeNumber) {
    final schedule = getSchedule(routeNumber);
    final now = DateTime.now();
    final last = _parseTime(schedule.lastBus, now);
    if (now.isAfter(last)) return 0;
    return last.difference(now).inMinutes;
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  static DateTime _parseTime(String hhmm, DateTime base) {
    final parts = hhmm.split(':');
    return DateTime(
      base.year, base.month, base.day,
      int.parse(parts[0] == '' ? '0' : parts[0]),
      int.parse(parts[1] == '' ? '0' : parts[1]),
    );
  }
}
