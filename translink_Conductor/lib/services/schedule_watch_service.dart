// ─────────────────────────────────────────────────────────────────────────────
// Schedule Watch Service  (WorkManager-based auto-start/stop)
//
// Registers a periodic background task (every 15 minutes) that:
//   1. Checks if current time is within the route's operating hours.
//   2. Starts the GPS foreground service when the shift begins.
//   3. Stops the GPS foreground service when the shift ends.
//
// The driver NEVER needs to open the app manually after their one-time
// registration. The phone handles everything.
//
// WorkManager fires even when the app is killed, phone is in Doze mode,
// or the screen is off — as long as battery optimization is disabled (we
// request this permission during registration).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../core/constants/driver_constants.dart';
import 'route_schedule_service.dart';
import 'supabase_service.dart';

// Task name constant (must be unique, consistent with registration).
const String _kTaskName      = 'translink_schedule_watch';
const String _kTaskUniqueName = 'translink_schedule_watch_daily';

/// Top-level callback — required by WorkManager.
/// MUST be a top-level or static function.
@pragma('vm:entry-point')
void workManagerCallback() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await _runScheduleWatch();
    } catch (e) {
      // Never throw — WorkManager retries on exception.
      return Future.value(false);
    }
    return Future.value(true);
  });
}

Future<void> _runScheduleWatch() async {
  final prefs = await SharedPreferences.getInstance();

  // Not registered → nothing to do.
  final isLoggedIn   = prefs.getBool(DriverConstants.keyIsLoggedIn) ?? false;
  final routeNumber  = prefs.getString(DriverConstants.keyRouteNumber) ?? '';
  final busNumber    = prefs.getString(DriverConstants.keyBusNumber) ?? '';
  if (!isLoggedIn || routeNumber.isEmpty || busNumber.isEmpty) return;

  final service    = FlutterBackgroundService();
  final isRunning  = await service.isRunning();
  final withinHours = RouteScheduleService.isWithinOperatingHours(routeNumber);

  if (withinHours && !isRunning) {
    // Shift has started — auto-kick GPS service.
    await prefs.setBool(DriverConstants.keyIsTracking, true);
    await SupabaseService.initialize();
    await service.startService();
  } else if (!withinHours && isRunning) {
    // Shift has ended — stop GPS service and clean up Supabase.
    await prefs.setBool(DriverConstants.keyIsTracking, false);
    await SupabaseService.initialize();
    await SupabaseService.removeLivePosition(busNumber);
    service.invoke('stopService');
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ScheduleWatchService {
  /// Initialise WorkManager — call this once from main() before runApp().
  /// [callbackDispatcher] must be the top-level [workManagerCallback] function.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    await Workmanager().initialize(workManagerCallback);
  }

  /// Register the periodic schedule-watch task.
  /// Call this once after the driver completes registration.
  /// Safe to call repeatedly — `existingWorkPolicy.replace` updates if already registered.
  static Future<void> registerPeriodicTask() async {
    if (kIsWeb) return;
    await Workmanager().registerPeriodicTask(
      _kTaskUniqueName,
      _kTaskName,
      // WorkManager minimum interval is 15 minutes — this is fine for our use.
      frequency: const Duration(minutes: 15),
      // Retry with exponential back-off on failure.
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
      // Replace existing task (safe for re-registration).
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      // Run even with low battery — tracking is critical.
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
      ),
    );
  }

  /// Cancel the periodic task — called on logout.
  static Future<void> cancelTask() async {
    if (kIsWeb) return;
    await Workmanager().cancelByUniqueName(_kTaskUniqueName);
  }
}
