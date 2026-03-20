

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../core/constants/driver_constants.dart';
import 'route_schedule_service.dart';
import 'supabase_service.dart';

const String _kTaskName      = 'translink_schedule_watch';
const String _kTaskUniqueName = 'translink_schedule_watch_daily';

@pragma('vm:entry-point')
void workManagerCallback() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await _runScheduleWatch();
    } catch (e) {

      return Future.value(false);
    }
    return Future.value(true);
  });
}

Future<void> _runScheduleWatch() async {
  final prefs = await SharedPreferences.getInstance();

  final isLoggedIn   = prefs.getBool(DriverConstants.keyIsLoggedIn) ?? false;
  final routeNumber  = prefs.getString(DriverConstants.keyRouteNumber) ?? '';
  final busNumber    = prefs.getString(DriverConstants.keyBusNumber) ?? '';
  if (!isLoggedIn || routeNumber.isEmpty || busNumber.isEmpty) return;

  final service    = FlutterBackgroundService();
  final isRunning  = await service.isRunning();
  final withinHours = RouteScheduleService.isWithinOperatingHours(routeNumber);

  if (withinHours && !isRunning) {

    await prefs.setBool(DriverConstants.keyIsTracking, true);
    await SupabaseService.initialize();
    await service.startService();
  } else if (!withinHours && isRunning) {

    await prefs.setBool(DriverConstants.keyIsTracking, false);
    await SupabaseService.initialize();
    await SupabaseService.removeLivePosition(busNumber);
    service.invoke('stopService');
  }
}

class ScheduleWatchService {

  static Future<void> initialize() async {
    if (kIsWeb) return;
    await Workmanager().initialize(workManagerCallback);
  }

  static Future<void> registerPeriodicTask() async {
    if (kIsWeb) return;
    await Workmanager().registerPeriodicTask(
      _kTaskUniqueName,
      _kTaskName,

      frequency: const Duration(minutes: 15),

      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),

      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,

      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
      ),
    );
  }

  static Future<void> cancelTask() async {
    if (kIsWeb) return;
    await Workmanager().cancelByUniqueName(_kTaskUniqueName);
  }
}