import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/driver_constants.dart';
import 'depot_detection_service.dart';
import 'route_schedule_service.dart';
import 'supabase_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// GPS broadcast interval (seconds) — used by both foreground and background.
const int _kBroadcastIntervalSeconds = 5;
const int _kScheduleCheckIntervalMinutes = 2;

class LocationService {
  // ── Foreground timer (primary broadcast mechanism) ─────────────────────────
  // This runs while the app is open and guarantees broadcasting even when
  // the background service fails to start (Android OEM restrictions).
  static Timer? _foregroundTimer;

  // ── Background service web fallback ────────────────────────────────────────
  static Timer? _webTimer;

  static DateTime _lastScheduleCheck = DateTime.fromMillisecondsSinceEpoch(0);
  static Position? _lastBroadcastPos;

  // ─────────────────────────────────────────────────── Background service setup

  static Future<void> initializeService() async {
    if (kIsWeb) return;

    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'driver_tracking_channel',
      'TransLink Driver Tracking',
      description: 'Keeps GPS active so passengers see your bus live.',
      importance: Importance.low,
    );

    final notif = FlutterLocalNotificationsPlugin();
    await notif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'driver_tracking_channel',
        initialNotificationTitle: 'TransLink Driver',
        initialNotificationContent: 'GPS active — passengers can see your bus.',
        foregroundServiceNotificationId: 888,
        autoStartOnBoot: false,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  // ─────────────────────────────────────────────── Platform-agnostic public API

  static Future<bool> isTracking() async {
    if (kIsWeb) return _webTimer != null;
    // Tracking if either the foreground timer OR background service is running.
    final bgRunning = await FlutterBackgroundService().isRunning();
    return _foregroundTimer != null || bgRunning;
  }

  /// Start broadcasting GPS.
  /// 1. Starts the foreground timer immediately (works in all conditions).
  /// 2. Also tries to start the background service (keeps working when app is closed).
  static Future<void> startTracking({String? accessToken, String? refreshToken}) async {
    if (kIsWeb) {
      _webTimer ??= Timer.periodic(
        const Duration(seconds: _kBroadcastIntervalSeconds),
        (_) => _performGpsTick(null, null),
      );
      return;
    }

    // 1. Recover session if not provided
    if (accessToken == null) {
      final session = SupabaseService.currentSession;
      accessToken = session?.accessToken;
      refreshToken = session?.refreshToken;
    }

    // 2. Acquire partial wakelock to ensure CPU doesn't sleep in Doze mode
    WakelockPlus.enable();

    final prefs = await SharedPreferences.getInstance();
    final busNumber = prefs.getString(DriverConstants.keyBusNumber) ?? '';

    // 3. Purge any existing live position for this bus BEFORE starting new broadcast.
    if (busNumber.isNotEmpty) {
      // Don't await indefinitely, but give it a bit of time to clear "ghost" markers
      await SupabaseService.removeLivePosition(busNumber).timeout(const Duration(seconds: 2), onTimeout: () {});
      debugPrint('🧹 Cleaned up stale ghost session for bus $busNumber');
    }

    // 4. Foreground timer: backup strategy
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(
      const Duration(seconds: _kBroadcastIntervalSeconds),
      (_) => _performGpsTick(null, null),
    );

    // 5. Background service: keeps running when app is minimised/killed
    final service = FlutterBackgroundService();
    
    if (!await service.isRunning()) {
      try {
        await service.startService();
        // If background service starts successfully, we don't need the foreground timer
        _foregroundTimer?.cancel();
        _foregroundTimer = null;
      } catch (e) {
        debugPrint('⚠️ Background service failed: $e — foreground timer is active.');
      }
    }

    // 6. PERSISTENT HANDOVER: Save tokens so background isolate can recover them immediately
    if (accessToken != null) {
      await prefs.setString('supabase_access_token', accessToken);
      if (refreshToken != null) {
        await prefs.setString('supabase_refresh_token', refreshToken);
      }
      
      service.invoke('updateSession', {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      });
    }

    // 7. Trigger first tick immediately (don't wait interval)
    unawaited(Future.delayed(const Duration(milliseconds: 1000), () => _performGpsTick(null, null)));
  }

  static Future<void> stopTracking() async {
    // Release wakelock
    if (!kIsWeb) WakelockPlus.disable();

    // Cancel foreground timer
    _foregroundTimer?.cancel();
    _foregroundTimer = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DriverConstants.keyIsTracking, false);

    if (kIsWeb) {
      final busNumber = prefs.getString(DriverConstants.keyBusNumber) ?? '';
      if (busNumber.isNotEmpty) await SupabaseService.removeLivePosition(busNumber);
      _webTimer?.cancel();
      _webTimer = null;
      return;
    }

    // Stop background service
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stopService');
    }
  }

  /// Manually fetch current GPS position.
  static Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (e) {
      debugPrint('🚨 getCurrentLocation error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────── Background service entry point

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    ui.DartPluginRegistrant.ensureInitialized();
    WakelockPlus.enable(); // Essential for background isolate
    final notif = FlutterLocalNotificationsPlugin();

    // Each background isolate needs its own Supabase init.
    await SupabaseService.initialize();

    service.on('stopService').listen((_) => service.stopSelf());
    service.on('updateSession').listen((data) async {
      if (data != null && data['accessToken'] != null) {
        await SupabaseService.setSession(data['accessToken'], data['refreshToken'] ?? '');
      }
    });

    // ✅ BOOT-UP AUTH RECOVERY: Read persisted tokens immediately
    final initialPrefs = await SharedPreferences.getInstance();
    final savedToken = initialPrefs.getString('supabase_access_token');
    final savedRefresh = initialPrefs.getString('supabase_refresh_token');
    if (savedToken != null) {
      await SupabaseService.setSession(savedToken, savedRefresh ?? '');
      debugPrint('🔑 [ZERO-FAIL] Background isolate recovered session from storage.');
    }

    _lastScheduleCheck = DateTime.fromMillisecondsSinceEpoch(0);

    Timer.periodic(const Duration(seconds: _kBroadcastIntervalSeconds), (timer) async {
      // ✅ RESILIENCE: Verify we still WANT to be tracking (persisted in prefs)
      final prefs = await SharedPreferences.getInstance();
      final isTracking = prefs.getBool(DriverConstants.keyIsTracking) ?? false;
      
      if (!isTracking) {
        timer.cancel();
        WakelockPlus.disable();
        service.stopSelf();
        return;
      }

      // Check for session in background if not set
      if (SupabaseService.currentSession == null) {
        debugPrint('⏳ Background isolate waiting for session...');
      }

      final shouldContinue = await _performGpsTick(service, notif);
      if (!shouldContinue) {
        timer.cancel();
        WakelockPlus.disable();
        await Future.delayed(const Duration(seconds: 3));
        service.stopSelf(); 
      }
    });
  }

  // ─────────────────────────────────────────────────── Core GPS broadcast tick

  /// One GPS fetch + Supabase push cycle.
  /// [service] and [notif] are null when called from the foreground timer.
  static Future<bool> _performGpsTick(
    ServiceInstance? service,
    FlutterLocalNotificationsPlugin? notif,
  ) async {
    final prefs     = await SharedPreferences.getInstance();
    final busNumber = prefs.getString(DriverConstants.keyBusNumber);
    final routeNum  = prefs.getString(DriverConstants.keyRouteNumber);
    final routeName = prefs.getString(DriverConstants.keyRouteName) ?? '';
    final fleetType = prefs.getString(DriverConstants.keyFleetType) ?? 'private';

    if (busNumber == null || busNumber.isEmpty ||
        routeNum  == null || routeNum.isEmpty) {
      _updateNotificationSafe(service, notif,
          title: 'TransLink Driver — Setup Required',
          body:  'Open the app to enter your bus details.');
      return true;
    }

    final headway = prefs.getInt(DriverConstants.keyHeadwayMinutes) ?? 20;

    // ── Schedule / operating-hours check (every 2 min) ────────────────────────
    final now = DateTime.now();
    if (now.difference(_lastScheduleCheck).inMinutes >= _kScheduleCheckIntervalMinutes) {
      _lastScheduleCheck = now;
      final withinHours = RouteScheduleService.isWithinOperatingHours(routeNum);

      if (!withinHours) {
        await prefs.setBool(DriverConstants.keyIsTracking, false);
        await SupabaseService.removeLivePosition(busNumber);
        _updateNotificationSafe(service, notif,
            title: 'Shift Ended — Route $routeNum',
            body:  'Tracking stopped. Have a safe journey home!');
        return false; // Stop background service loop
      }

      final minsLeft = RouteScheduleService.minutesUntilLastBus(routeNum);
      if (minsLeft > 0 && minsLeft <= headway) {
        _updateNotificationSafe(service, notif,
            title: 'TransLink — Last Run Soon',
            body:  'Route $routeNum ends in ~$minsLeft min.');
      }
    }
    try {
      // ── GPS broadcast ─────────────────────────────────────────────────────────
      // ✅ RECOVERY: Use a simpler fetch without strict AndroidSettings timeout for the first fix
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );

      double lat = pos.latitude;
      double lng = pos.longitude;
      double heading = pos.heading;
      final currentSpeed = pos.speed < 0 ? 0.0 : pos.speed;
      final speedKmph = currentSpeed * 3.6;

      // 🛑 ADVANCED ANTI-JITTER & RANGE FILTER
      if (_lastBroadcastPos != null) {
        final dist = Geolocator.distanceBetween(
          _lastBroadcastPos!.latitude, _lastBroadcastPos!.longitude,
          pos.latitude, pos.longitude,
        );

        // 1. Dead Band: If shifted < 10m while moving slow, it's likely GPS noise.
        // This keeps the bus icon perfectly still at bus stops.
        if (dist < 10.0 && speedKmph < 5.0) {
          lat = _lastBroadcastPos!.latitude;
          lng = _lastBroadcastPos!.longitude;
          heading = _lastBroadcastPos!.heading;
        } else {
          // 2. Linear Smoothing (LERP): Average with last known to prevent "jumps"
          lat = (_lastBroadcastPos!.latitude + pos.latitude) / 2;
          lng = (_lastBroadcastPos!.longitude + pos.longitude) / 2;
          // Only update heading if moved significantly to avoid spinning
          if (dist < 2.0 && speedKmph < 2.0) {
            heading = _lastBroadcastPos!.heading;
          }
          _lastBroadcastPos = Position(
            latitude: lat, longitude: lng, timestamp: pos.timestamp, 
            accuracy: pos.accuracy, altitude: pos.altitude, heading: heading, 
            speed: pos.speed, speedAccuracy: pos.speedAccuracy, 
            altitudeAccuracy: pos.altitudeAccuracy, headingAccuracy: pos.headingAccuracy,
          );
        }
      } else {
        _lastBroadcastPos = pos;
      }

      final speedMs   = pos.speed < 0 ? 0.0 : pos.speed;
      final firstBus  = prefs.getString(DriverConstants.keyFirstBus) ?? '05:30';
      final busStatus = await DepotDetectionService.evaluate(
        routeNumber: routeNum,
        lat: lat,
        lng: lng,
        speedMs: speedMs,
        firstBus: firstBus,
      );
      final statusStr = DepotDetectionService.statusLabel(busStatus);
      final nextDue   = RouteScheduleService.computeNextBusDue(routeNum);

      int batteryLevel = 100;
      try { batteryLevel = await Battery().batteryLevel; } catch (_) {}

      // ✅ Write to Supabase with smoothed coords
      final error = await SupabaseService.updateLivePosition(
        busNumber:      busNumber,
        routeNumber:    routeNum,
        routeName:      routeName,
        lat:            lat,
        lng:            lng,
        speed:          speedMs,
        heading:        heading < 0 ? 0 : heading,
        headwayMinutes: headway,
        nextBusDueAt:   nextDue,
        status:         statusStr,
        fleetType:      fleetType,
      );

      if (error != null) {
        debugPrint('🚨 [REWRITE] Tick Error: $error');
        if (service != null) {
          service.invoke('trackingError', {'message': error});
        }
      }

      // ❌ REMOVED: Auto-setting keyIsTracking = true.
      // This caused the "Auto-Restart" bug because it would overwrite a manual stop during a race condition.
      // await prefs.setBool(DriverConstants.keyIsTracking, true);

      // Update notification (background mode only)
      if (service != null && notif != null) {
        final schedule = RouteScheduleService.getSchedule(routeNum);
        String notifBody = switch (busStatus) {
          BusStatus.onRoute  => '${schedule.frequencyLabel} · Broadcasting to passengers',
          BusStatus.atDepot  => 'At Bus Stand – will go live on departure',
          BusStatus.stopped  => 'Temporary stop – passengers notified',
          BusStatus.preShift => 'Pre-shift – tracking begins at ${schedule.firstBus}',
          BusStatus.offRoute => 'Off Route — tracking paused',
        };
        String notifTitle = busStatus == BusStatus.onRoute
            ? 'LIVE – Route $routeNum'
            : 'Route $routeNum – ${busStatus.name}';

        if (batteryLevel <= 20) {
          notifTitle = '⚠️ BATTERY LOW ($batteryLevel%) – Connect Charger!';
        }
        _updateNotificationSafe(service, notif, title: notifTitle, body: notifBody);
      }
    } on LocationServiceDisabledException {
      _updateNotificationSafe(service, notif,
          title: 'GPS Disabled',
          body:  'Please enable Location Services.');
    } on TimeoutException {
      _updateNotificationSafe(service, notif,
          title: 'Route $routeNum – GPS Timeout',
          body:  'Retrying in ${_kBroadcastIntervalSeconds}s…');
    } catch (e) {
      debugPrint('🚨 _performGpsTick error: $e');
      _updateNotificationSafe(service, notif,
          title: 'Route $routeNum – Retrying…',
          body:  'GPS error. Will retry automatically.');
    }
    return true;
  }

  // ───────────────────────────────────────────────────────── Notification helper

  static void _updateNotificationSafe(
    ServiceInstance? service,
    FlutterLocalNotificationsPlugin? notif, {
    required String title,
    required String body,
  }) {
    if (service == null || notif == null) return;
    _updateNotification(service, notif, title: title, body: body);
  }

  static Future<void> _updateNotification(
    ServiceInstance service,
    FlutterLocalNotificationsPlugin notif, {
    required String title,
    required String body,
  }) async {
    if (service is AndroidServiceInstance) {
      await notif.show(
        id: 888,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'driver_tracking_channel',
            'TransLink Driver Tracking',
            channelDescription: 'Keeps GPS active so passengers see your bus live.',
            icon: '@mipmap/ic_launcher',
            ongoing: true,
            priority: Priority.low,
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
        ),
      );
    }
  }
}
