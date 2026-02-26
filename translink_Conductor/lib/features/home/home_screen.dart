import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/driver_constants.dart';
import '../../core/utils/error_handler.dart';
import '../../services/route_schedule_service.dart';
import '../../services/schedule_watch_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart'; // Added
import '../../services/supabase_service.dart';
import '../../services/location_service.dart';
import '../setup/setup_screen.dart';
import '../../core/utils/app_localizations.dart';
import '../../core/services/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import './widgets/fare_calculator_sheet.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
// import 'package:share_plus/share_plus.dart';

// ── Problem types the driver can report ─────────────────────────────────────

class _ProblemOption {
  final String code;       // stored as 'status' in Supabase
  final String label;
  final String emoji;
  final String description;
  final Color color;

  const _ProblemOption({
    required this.code,
    required this.label,
    required this.emoji,
    required this.description,
    required this.color,
  });
}

const List<_ProblemOption> _problemOptions = [
  _ProblemOption(
    code: 'breakdown',
    label: 'Breakdown', // We'll use l10n.translate(opt.code) in UI
    emoji: '🔧',
    description: 'Vehicle has broken down and cannot continue.',
    color: Color(0xFFDC2626),
  ),
  _ProblemOption(
    code: 'accident',
    label: 'Accident',
    emoji: '🚨',
    description: 'Involved in or blocked by an accident.',
    color: Color(0xFFEA580C),
  ),
  _ProblemOption(
    code: 'medical_emergency',
    label: 'Medical Emergency',
    emoji: '🏥',
    description: 'Passenger medical emergency onboard.',
    color: Color(0xFF0EA5E9),
  ),
];

// ── Screen ───────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _busNumber     = '';
  String _routeNumber   = '';
  String _routeName     = '';
  String _scheduleLabel = '';
  String _firstBus      = '';
  String _lastBus       = '';
  int    _headway       = 20;
  bool   _isTracking    = false;
  bool   _withinHours   = false;
  int    _minsLeft      = 0;
  String _syncStatus    = 'Offline'; // Added: Real-time sync diagnostic
  Color  _syncColor     = const Color(0xFF64748B);

  /// 'on_time' | 'breakdown' | 'accident' | 'heavy_traffic' | … (see _problemOptions)
  String _currentStatus = 'on_time';

  Timer? _refreshTimer;
  double _tripRevenue = 0.0;
  int _passengerCount = 0;
  final _manualFareCtrl = TextEditingController(text: '30'); // Default min fare
  int _currentTab = 0;
  DateTime? _lastScan;
  StreamSubscription? _revenueSub;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAndAutoStart();
    _initRevenueStream();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshState());

    // 🛡️ Listen for background tracking errors (e.g. RLS Rejection)
    FlutterBackgroundService().on('trackingError').listen((event) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final rawMsg = event?['message'] ?? 'Database Sync Error';
      final msg = _getReadableErrorMessage(rawMsg, l10n);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ $msg'),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  void _initRevenueStream() async {
    final prefs = await SharedPreferences.getInstance();
    final busNum = prefs.getString(DriverConstants.keyBusNumber) ?? '';
    if (busNum.isEmpty) return;

    _revenueSub?.cancel();
    _revenueSub = SupabaseService.getRevenueHistoryStream(busNum).listen((transactions) {
      if (!mounted) return;
      
      final sessionStartStr = prefs.getString('lastRouteStartedAt');
      final sessionStart = sessionStartStr != null ? DateTime.parse(sessionStartStr) : DateTime(2000);

      double sessionTotal = 0;
      int sessionCount = 0;

      for (var tx in transactions) {
        try {
          final txDate = DateTime.tryParse(tx['created_at'] ?? '') ?? DateTime(0);
          if (txDate.isAfter(sessionStart)) {
            final rawAmount = tx['amount'];
            if (rawAmount != null) {
              sessionTotal += (rawAmount as num).toDouble();
              sessionCount++;
            }
          }
        } catch (e) {
          debugPrint('⚠️ [Revenue] Skipping malformed tx: $e');
        }
      }
      
      setState(() {
        _tripRevenue = sessionTotal;
        _passengerCount = sessionCount;
      });
      debugPrint('💰 [REWRITE] Session Revenue: $sessionTotal ($sessionCount txs) since $sessionStart');
    }, onError: (e) {
      debugPrint('🚨 [Revenue Stream Error] $e');
    });
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _revenueSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAndAutoStart();
      _initRevenueStream(); // Re-establish data stream and refresh counters
    }
  }

  // ── Auto-start logic ───────────────────────────────────────────────────────

  Future<void> _loadAndAutoStart() async {
    // Just refresh the UI state. We don't auto-start tracking anymore 
    // to give conductor manual control.
    await _refreshState();
  }

  Future<void> _refreshState() async {
    final prefs     = await SharedPreferences.getInstance();
    final routeNum  = prefs.getString(DriverConstants.keyRouteNumber) ?? '';
    final isRunning = await LocationService.isTracking();

    if (!mounted) return;
    setState(() {
      _busNumber     = prefs.getString(DriverConstants.keyBusNumber)     ?? '';
      _routeNumber   = routeNum;
      _routeName     = prefs.getString(DriverConstants.keyRouteName)     ?? '';
      _scheduleLabel = prefs.getString(DriverConstants.keyScheduleLabel) ?? '';
      _firstBus      = prefs.getString(DriverConstants.keyFirstBus)      ?? '';
      _lastBus       = prefs.getString(DriverConstants.keyLastBus)       ?? '';
      _headway       = prefs.getInt(DriverConstants.keyHeadwayMinutes)   ?? 20;
      _currentStatus = prefs.getString('currentStatus')                  ?? 'on_time';
      _isTracking    = isRunning && (prefs.getBool(DriverConstants.keyIsTracking) ?? false);

      // Fetch real operating hours if they belong to a known schedule
      final schedule = RouteScheduleService.getSchedule(routeNum);
      _firstBus = schedule.firstBus; // Use the service as source of truth
      _lastBus  = schedule.lastBus;

      _withinHours   = routeNum.isNotEmpty
          ? RouteScheduleService.isWithinOperatingHours(routeNum)
          : false;
      _minsLeft = routeNum.isNotEmpty
          ? RouteScheduleService.minutesUntilLastBus(routeNum)
          : 0;
    });

    // AUTO-STOP: shift ended
    if (_isTracking && !_withinHours && !kIsWeb) {
      await _doStopTracking(silent: true);
    }
  }

  // ── Tracking controls ──────────────────────────────────────────────────────

  Future<void> _startTrackingManually() async {
    final prefs = await SharedPreferences.getInstance();
    final l10n = AppLocalizations.of(context)!;
    
    setState(() {
      _syncStatus = '🛰️ Getting GPS...';
      _syncColor  = Colors.orange;
    });

    // 1. RECOVERY: Direct Initial Sync in UI Thread
    // This bypasses the background isolate for the very first link to catch errors
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high)
      ).timeout(const Duration(seconds: 15));

      setState(() { _syncStatus = '📡 Linking DB...'; });

      final error = await SupabaseService.updateLivePosition(
        busNumber:   _busNumber,
        routeNumber: _routeNumber,
        routeName:   _routeName,
        lat:         pos.latitude,
        lng:         pos.longitude,
        speed:       pos.speed,
        heading:     pos.heading,
        headwayMinutes: _headway,
      );

      if (error != null) {
        // 🚨 CRITICAL RECOVERY: If it's an Auth error, don't just show a Snackbar.
        // Force a logout so the user can re-authenticate.
        if (error.contains('Auth') || error.contains('session')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🔔 Session expired. Please login again.'),
                backgroundColor: Color(0xFFDC2626),
              ),
            );
            _logout(); // Re-authenticate automatically
          }
          return;
        }
        throw Exception(error);
      }

      setState(() {
        _syncStatus = '✅ Online';
        _syncColor  = const Color(0xFF10B981);
      });
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        _showErrorSnackBar(e);
        setState(() {
          _syncStatus = l10n.translate('sync_failed');
          _syncColor  = Colors.red;
        });
      }
      return; // Abort starting service if initial sync fails
    }
    
    // START NEW SESSION: Reset transit data for this specific trip
    final startTime = DateTime.now().toUtc().toIso8601String();
    await prefs.setString('lastRouteStartedAt', startTime);
    await prefs.setBool(DriverConstants.keyIsTracking, true);

    // 2. Launch background service for persistence
    final session = SupabaseService.currentSession;
    await LocationService.startTracking(
      accessToken: session?.accessToken,
      refreshToken: session?.refreshToken,
    );

    await _refreshState();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('tracking_started_msg')), 
          backgroundColor: const Color(0xFF10B981)
        ),
      );
    }
  }

  Future<void> _stopTrackingManually() async {
    await _doStopTracking(silent: false);
  }

  Future<void> _doStopTracking({required bool silent}) async {
    await LocationService.stopTracking();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DriverConstants.keyIsTracking, false);
    // Clear any problem status when stopping
    await prefs.setString('currentStatus', 'on_time');
    if (_busNumber.isNotEmpty) {
      await SupabaseService.removeLivePosition(_busNumber);
    }
    await _refreshState();
    if (!silent && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('tracking_stopped_msg'))),
      );
    }
  }

  // ── Problem reporting ──────────────────────────────────────────────────────

  Future<void> _showProblemSheet() async {
    if (!_isTracking) return;

    final selected = await showModalBottomSheet<_ProblemOption>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProblemSheetContent(currentCode: _currentStatus),
    );

    if (selected == null) return; // dismissed without selection

    // Toggle:  tapping the same problem again clears it
    final newCode = (selected.code == _currentStatus) ? 'on_time' : selected.code;
    await _applyStatus(newCode);
  }

  Future<void> _clearProblem() async {
    await _applyStatus('on_time');
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('status_cleared')),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _applyStatus(String code) async {
    setState(() => _currentStatus = code);

    // Persist so the next GPS update from the background service carries it
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentStatus', code);

    if (_busNumber.isNotEmpty) {
      await SupabaseService.updateLivePosition(
        busNumber: _busNumber,
        routeNumber: _routeNumber,
        routeName: _routeName,
        lat: 0,
        lng: 0,
        status: code,
        headwayMinutes: _headway,
      );
    }

    if (mounted && code != 'on_time') {
      final l10n = AppLocalizations.of(context)!;
      final opt = _problemOptions.firstWhere((o) => o.code == code, orElse: () => _problemOptions[0]);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('reported_msg', args: {'emoji': opt.emoji, 'label': l10n.translate(opt.code)})),
          backgroundColor: opt.color,
          action: SnackBarAction(
            label: l10n.translate('clear'),
            textColor: Colors.white,
            onPressed: _clearProblem,
          ),
        ),
      );
    }
  }

  // ── Conductor Actions ──────────────────────────────────────────────────────



  Future<void> _processScanResult(String code) async {
    if (_lastScan != null && DateTime.now().difference(_lastScan!) < const Duration(seconds: 2)) return;
    _lastScan = DateTime.now();

    try {
      // 🛡️ ULTRA-DEFENSIVE PARSING
      final dynamic decoded = json.decode(code);
      if (decoded is! Map) throw "Invalid QR code format: Not a JSON map.";
      
      final passengerId = (decoded['uid'] ?? decoded['id'])?.toString();
      if (passengerId == null || passengerId.isEmpty) throw "Invalid QR code: Missing user ID.";

      // --- Fare Priority Logic ---
      double fare;
      String? passengerDest;
      if (decoded['fare'] != null) {
        // Use Official Fare from Passenger's QR (Prevents overcharging)
        fare = (decoded['fare'] as num).toDouble();
        passengerDest = decoded['dest']?.toString();
      } else {
        // Fallback to manual entry for simple UID-only QRs
        fare = double.tryParse(_manualFareCtrl.text) ?? 30.0;
      }
      if (fare <= 0) fare = 30.0; // Fail-safe

      if (!mounted) return;
      setState(() => _isProcessing = true);

      // 🛰️ GET POS-LOCK (OPTIONAL BUT DEFENSIVE)
      String stopName = "Station near current location";
      try {
        final pos = await LocationService.getCurrentLocation();
        if (pos != null) {
          stopName = _getNearbyStationName(pos.latitude, pos.longitude);
        }
      } catch (_) {}

      final error = await SupabaseService.processPayment(
        passengerId: passengerId,
        amount: fare,
        busNumber: _busNumber,
        routeNumber: _routeNumber,
        startStop: stopName,
        endStop: passengerDest ?? _getEndStationName(),
      );

      if (!mounted) return;

      if (error == null) {
        _showSuccessFeedback(fare);
        // ⚡ INSTANT LOCAL SYNC: Prevent revenue from staying at zero
        setState(() {
          _tripRevenue += fare;
          _passengerCount += 1;
        });
      } else {
        _showErrorSnackBar(error);
      }
    } catch (e) {
      debugPrint('🚨 [REWRITE] Scan Error: $e');
      if (mounted) _showErrorSnackBar('Scan Error: Invalid QR or Connection');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSuccessFeedback(double amount) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.translate('payment_success_msg', args: {'amount': amount.toStringAsFixed(0)}),
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
    ));
  }

  String _getReadableErrorMessage(dynamic error, AppLocalizations l10n) {
    final String msg = error.toString().toLowerCase();
    
    // Check for common network/database error keywords
    if (msg.contains('socketexception') || 
        msg.contains('failed host lookup') || 
        msg.contains('clientexception') ||
        msg.contains('network') ||
        msg.contains('http') ||
        msg.contains('connection')) {
      return l10n.translate('no_internet');
    }
    
    if (msg.contains('auth') || msg.contains('session') || msg.contains('jwt')) {
      return l10n.translate('login_required'); // Fallback to localized re-auth msg
    }

    if (msg.contains('fleet_type')) {
      return 'System Update Required: Please add the fleet_type column to Supabase.';
    }

    if (msg.contains('pgrst204')) {
      return 'System Outdated: Database structure needs update.';
    }

    return error.toString();
  }

  void _showErrorSnackBar(dynamic error) {
    final msg = ErrorHandler.getFriendlyMessage(error, context);
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(msg)),
        ],
      ),
      backgroundColor: const Color(0xFFDC2626),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _scanQR() async {
    if (!_isTracking) return;
    
    final String? result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'QR Scanner',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, anim1, anim2) {
        return const _QRScannerDialog();
      },
    );

    if (result != null && mounted) {
       _processScanResult(result);
    }
  }

  Future<void> _openManualFare() async {
    final amount = double.tryParse(_manualFareCtrl.text) ?? 30.0;
    
    // Sync manual fare with database
    final error = await SupabaseService.processPayment(
      passengerId: null, // No UID for manual entry
      amount: amount,
      busNumber: _busNumber,
      routeNumber: _routeNumber,
    );

    if (!mounted) return;

    if (error == null) {
      _showSuccessFeedback(amount);
      // ⚡ INSTANT LOCAL SYNC: Prevent revenue from staying at zero
      setState(() {
        _tripRevenue += amount;
        _passengerCount += 1;
      });
      
      // Clear the field for next entry
      _manualFareCtrl.text = "30"; 
    } else {
      _showErrorSnackBar(error);
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  void _confirmLogout() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.translate('logout_title'), style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20)),
        content: Text(
          l10n.translate('logout_msg'),
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel'), style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () { Navigator.pop(context); _logout(); },
            child: Text(l10n.translate('logout'), style: GoogleFonts.inter(color: const Color(0xFFDC2626), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await LocationService.stopTracking();
    if (_busNumber.isNotEmpty) {
      await SupabaseService.removeLivePosition(_busNumber);
    }
    await ScheduleWatchService.cancelTask();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SetupScreen()));
    }
  }

  Widget _buildMetricBadge(BuildContext context, {required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: _currentTab == 0,
      onPopInvoked: (didPop) {
        if (!didPop && _currentTab != 0) {
          setState(() => _currentTab = 0);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildAppBar(),
                  Expanded(
                    child: _currentTab == 0 ? _buildRouteTab() : _buildRevenueTab(),
                  ),
                  _buildPersistentStatus(),
                ],
              ),
            ),
            if (_isProcessing)
              Container(
                color: Colors.black.withOpacity(0.4),
                child: const Center(
                  child: Card(
                    elevation: 8,
                    shape: CircleBorder(),
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(
                        color: Color(0xFF2563EB),
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))],
          ),
          child: BottomNavigationBar(
            currentIndex: _currentTab,
            onTap: (i) => setState(() => _currentTab = i),
            selectedItemColor: const Color(0xFF2563EB),
            unselectedItemColor: const Color(0xFF94A3B8),
            showUnselectedLabels: true,
            selectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 11),
            items: [
              BottomNavigationBarItem(icon: const Icon(Icons.route_rounded), activeIcon: const Icon(Icons.route_rounded), label: l10n.translate('home_tab')),
              BottomNavigationBarItem(icon: const Icon(Icons.payments_rounded), activeIcon: const Icon(Icons.payments_rounded), label: l10n.translate('revenue_tab')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteTab() {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (!_isTracking) ...[
            _buildStatusCircle(),
            const SizedBox(height: 32),
            _buildLargeStartButton(),
          ] else ...[
            // Status is now gracefully shown in the AppBar badge
            _buildControlPanel(),
          ],
        ],
      ),
    );
  }

  Widget _buildRevenueTab() {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRevenueCard(),
          const SizedBox(height: 24),
          Text(l10n.translate('bus_details_title'), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
          const SizedBox(height: 12),
          _buildInfoCard(),
          const SizedBox(height: 16),
          _buildScheduleCard(),
          const SizedBox(height: 24),
          _buildProblemButton(),
        ],
      ),
    );
  }

  Widget _buildLargeStartButton() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      height: 160,
      child: ElevatedButton(
        onPressed: _startTrackingManually,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 8,
          shadowColor: const Color(0xFF10B981).withOpacity(0.4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_fill_rounded, size: 48),
            const SizedBox(height: 12),
            Text(l10n.translate('start_route'), style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }


  Widget _buildProblemButton() {
    final l10n = AppLocalizations.of(context)!;
    final bool hasProblem = _currentStatus != 'on_time';
    final activeOpt = hasProblem ? _problemOptions.firstWhere((o) => o.code == _currentStatus, orElse: () => _problemOptions[0]) : null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isTracking ? _showProblemSheet : null,
        icon: Icon(hasProblem ? Icons.error_rounded : Icons.report_problem_rounded),
        label: Text(hasProblem ? l10n.translate(activeOpt!.code) : l10n.translate('report_problem')),
        style: ElevatedButton.styleFrom(
          backgroundColor: hasProblem ? activeOpt!.color.withOpacity(0.1) : Colors.white,
          foregroundColor: hasProblem ? activeOpt!.color : const Color(0xFFEA580C),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: hasProblem ? activeOpt!.color : const Color(0xFFEA580C).withOpacity(0.2))),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final l10n = AppLocalizations.of(context)!;
    final settings = Provider.of<SettingsProvider>(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.directions_bus_rounded, color: Color(0xFF2563EB), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('conductor_portal'),
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18, color: const Color(0xFF1E293B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${l10n.translate('bus_label')} $_busNumber · ${l10n.translate('route_label')} $_routeNumber',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout_rounded, size: 22, color: Color(0xFFDC2626)),
                tooltip: l10n.translate('logout'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 📡 SYSTEM SYNC STATUS (Hardened Badge)
          Row(
            children: [
              _buildMetricBadge(
                context,
                icon: Icons.sync_rounded,
                label: _syncStatus,
                color: _syncColor,
              ),
              const SizedBox(width: 8),
              if (_isTracking)
                _buildMetricBadge(
                  context,
                  icon: Icons.timer_outlined,
                  label: '$_minsLeft mins left',
                  color: _minsLeft < 30 ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Language Selector
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(Icons.language_rounded, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Text(
                        l10n.translate('language'),
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        onSelected: settings.setLanguage,
                        offset: const Offset(0, 40),
                        child: Row(
                          children: [
                            Text(
                              settings.languageName,
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF2563EB)),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded, color: const Color(0xFF2563EB)),
                            const SizedBox(width: 8),
                          ],
                        ),
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'English', child: Text('English')),
                          const PopupMenuItem(value: 'සිංහල', child: Text('සිංහල')),
                          const PopupMenuItem(value: 'தமிழ்', child: Text('தமிழ்')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPersistentStatus() {
    final l10n = AppLocalizations.of(context)!;
    final color = _isTracking ? const Color(0xFF10B981) : const Color(0xFFF43F5E);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: color,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_isTracking ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              l10n.translate(_isTracking ? 'tracking_started_msg' : 'tracking_stopped_msg').toUpperCase(),
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCircle() {
    final bool hasProblem = _currentStatus != 'on_time';
    final _ProblemOption? activeOpt = hasProblem
        ? _problemOptions.firstWhere((o) => o.code == _currentStatus, orElse: () => _problemOptions[0])
        : null;
    final l10n = AppLocalizations.of(context)!;
    final Color ringColor;
    final Color bgColor;
    final IconData icon;
    final String title;
    final String sub;

    if (hasProblem && _isTracking) {
      ringColor = activeOpt!.color;
      bgColor   = activeOpt.color.withValues(alpha: 0.08);
      icon      = Icons.warning_amber_rounded;
      title     = '${activeOpt.emoji} ${l10n.translate(activeOpt.code).toUpperCase()}';
      sub       = l10n.translate('reported_to_passengers');
    } else if (_isTracking && _withinHours) {
      ringColor = const Color(0xFF10B981);
      bgColor   = const Color(0xFF10B981).withValues(alpha: 0.08);
      icon      = Icons.wifi_tethering_rounded;
      title     = l10n.translate('live_broadcasting');
      sub       = l10n.translate('passengers_see_bus');
    } else if (!_isTracking) {
      ringColor = const Color(0xFFDC2626);
      bgColor   = const Color(0xFFDC2626).withValues(alpha: 0.08);
      icon      = Icons.wifi_tethering_off_rounded;
      title     = l10n.translate('tracking_stopped');
      sub       = l10n.translate('start_tracking_to_resume');
    } else if (!_withinHours && _routeNumber.isNotEmpty) {
      ringColor = const Color(0xFF94A3B8);
      bgColor   = const Color(0xFF94A3B8).withValues(alpha: 0.08);
      icon      = Icons.bedtime_rounded;
      title     = l10n.translate('outside_hours');
      sub       = l10n.translate('tracking_auto_stopped');
    } else {
      ringColor = const Color(0xFFF59E0B);
      bgColor   = const Color(0xFFF59E0B).withValues(alpha: 0.08);
      icon      = Icons.hourglass_top_rounded;
      title     = l10n.translate('starting');
      sub       = l10n.translate('connecting_gps');
    }

    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.9, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (_, val, child) => Transform.scale(scale: val, child: child),
          child: Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(color: ringColor, width: 4),
              boxShadow: [BoxShadow(color: ringColor.withValues(alpha: 0.2), blurRadius: 24, spreadRadius: 4)],
            ),
            child: Center(child: Icon(icon, color: ringColor, size: 56)),
          ),
        ),
        const SizedBox(height: 16),
        Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: ringColor, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(sub, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8))),
      ],
    );
  }

  Widget _buildInfoCard() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final double itemWidth = (constraints.maxWidth - 32) / 3;
        final bool isVeryNarrow = constraints.maxWidth < 280;

        if (isVeryNarrow) {
          return Column(children: [
            _infoBlock(Icons.confirmation_number_rounded, l10n.translate('bus_short'),   _busNumber.isNotEmpty ? _busNumber : '—'),
            const Divider(height: 24),
            _infoBlock(Icons.route_rounded,               l10n.translate('route_short'), _routeNumber.isNotEmpty ? _routeNumber : '—'),
            const Divider(height: 24),
            _infoBlock(Icons.timer_outlined,              l10n.translate('every_short'), _headway > 0 ? '$_headway ${l10n.translate('min_label')}' : '—'),
          ]);
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(width: itemWidth, child: _infoBlock(Icons.confirmation_number_rounded, l10n.translate('bus_short'),   _busNumber.isNotEmpty ? _busNumber : '—')),
            Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
            SizedBox(width: itemWidth, child: _infoBlock(Icons.route_rounded,               l10n.translate('route_short'), _routeNumber.isNotEmpty ? _routeNumber : '—')),
            Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
            SizedBox(width: itemWidth, child: _infoBlock(Icons.timer_outlined,              l10n.translate('every_short'), _headway > 0 ? '$_headway ${l10n.translate('min_label')}' : '—')),
          ],
        );
      }),
    );
  }

  Widget _infoBlock(IconData icon, String label, String value) {
    return Column(children: [
      Icon(icon, color: const Color(0xFF2563EB), size: 20),
      const SizedBox(height: 6),
      Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8), letterSpacing: 1)),
      const SizedBox(height: 4),
      Text(value, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
    ]);
  }

  Widget _buildScheduleCard() {
    final l10n = AppLocalizations.of(context)!;
    if (_routeNumber.isEmpty) return const SizedBox.shrink();

    final nearEnd = _minsLeft > 0 && _minsLeft <= _headway * 2;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: nearEnd ? const Color(0xFFFFFBEB) : const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: nearEnd ? const Color(0xFFFDE68A) : const Color(0xFFBFDBFE)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calendar_today_rounded, color: Color(0xFF2563EB), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.translate('route_schedule'), style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF1E293B)))),
        ]),
        const SizedBox(height: 12),
        _sRow(l10n.translate('route_name'), _routeName),
        const SizedBox(height: 6),
        _sRow(l10n.translate('operating_hours'), '$_firstBus – $_lastBus'),
        const SizedBox(height: 6),
        _sRow(l10n.translate('frequency'), _scheduleLabel.isNotEmpty ? _scheduleLabel : l10n.translate('every_min', args: {'min': '$_headway'})),
        if (_withinHours && _minsLeft > 0) ...[
          const SizedBox(height: 6),
          _sRow(l10n.translate('last_bus_in'), '$_minsLeft ${l10n.translate('min_label')}', valueColor: nearEnd ? const Color(0xFFD97706) : null),
        ],
      ]),
    );
  }

  Widget _sRow(String label, String value, {Color? valueColor}) {
    return Row(children: [
      Text('$label: ', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
      Expanded(child: Text(value, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: valueColor ?? const Color(0xFF1E293B)))),
    ]);
  }


  // ── Control Panel ──────────────────────────────────────────────────────────

  Widget _buildControlPanel() {
    final bool hasProblem = _currentStatus != 'on_time';
    final _ProblemOption? activeOpt = hasProblem
        ? _problemOptions.firstWhere((o) => o.code == _currentStatus, orElse: () => _problemOptions[0])
        : null;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.flash_on_rounded, color: Color(0xFF2563EB), size: 18),
            const SizedBox(width: 8),
            Text(l10n.translate('quick_actions').toUpperCase(), style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF1E293B), letterSpacing: 1)),
          ]),
          const SizedBox(height: 16),

          // ─── Main Action Row: SCAN QR ────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  height: 100,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l10n.translate('fare_label').toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                      TextField(
                        controller: _manualFareCtrl,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 100,
                  child: ElevatedButton(
                    onPressed: _isTracking ? _scanQR : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0xFF2563EB).withOpacity(0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.qr_code_scanner_rounded, size: 32),
                        const SizedBox(height: 4),
                        Text(l10n.translate('scan_qr_btn').toUpperCase(),
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ─── Second Row: Manual Fare & Report ────────────────────────
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isTracking ? _openManualFare : null,
                icon: const Icon(Icons.calculate_rounded),
                label: Text(l10n.translate('manual_entry') ?? 'MANUAL FARE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                  foregroundColor: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isTracking ? _showProblemSheet : null,
                icon: Icon(hasProblem ? Icons.error_rounded : Icons.report_problem_rounded),
                label: Text(hasProblem ? l10n.translate(activeOpt!.code) : l10n.translate('report_problem')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasProblem ? activeOpt!.color.withOpacity(0.1) : const Color(0xFFFFF7ED),
                  foregroundColor: hasProblem ? activeOpt!.color : const Color(0xFFEA580C),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ─── START / STOP TRACKING ──────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: _isTracking 
              ? OutlinedButton.icon(
                  onPressed: _stopTrackingManually,
                  icon: const Icon(Icons.stop_circle_rounded, color: Color(0xFFDC2626)),
                  label: Text(l10n.translate('stop_route_btn').toUpperCase(), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: const Color(0xFFDC2626), letterSpacing: 0.5)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Color(0xFFFEE2E2), width: 2),
                    backgroundColor: const Color(0xFFFEF2F2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                )
              : ElevatedButton.icon(
                  onPressed: _startTrackingManually,
                  icon: const Icon(Icons.play_circle_rounded),
                  label: Text(l10n.translate('start_route_btn').toUpperCase()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF1E293B).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Text(l10n.translate('trip_revenue_title').toUpperCase(),
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.5), letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Rs. ', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
              Text(_tripRevenue.toStringAsFixed(0), style: GoogleFonts.outfit(fontSize: 42, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_alt_rounded, color: Colors.white60, size: 14),
                const SizedBox(width: 6),
                Text(l10n.translate('passengers_count', args: {'count': '$_passengerCount'}), 
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _showRevenueHistoryModal,
            icon: const Icon(Icons.history_rounded, color: Color(0xFF10B981), size: 16),
            label: Text(l10n.translate('view_history'), 
              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 0.5)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              backgroundColor: Colors.white.withOpacity(0.05),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRevenueHistoryModal() async {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => _RevenueHistoryContent(
          busNumber: _busNumber,
          scrollController: scrollController,
        ),
      ),
    );
  }
  String _getNearbyStationName(double lat, double lng) {
    if (lat > 6.840 && lat < 6.865 && lng > 79.910 && lng < 79.935) return "Maharagama Town";
    if (lat > 6.835 && lat < 6.855 && lng > 79.950 && lng < 79.975) return "Kottawa Junction";
    if (lat > 6.835 && lat < 6.850 && lng > 79.990 && lng < 80.010) return "Homagama Junction";
    if (lat > 6.870 && lat < 6.890 && lng > 79.880 && lng < 79.910) return "Nugegoda Area";
    if (lat > 6.910 && lat < 6.940 && lng > 79.840 && lng < 79.870) return "Colombo Fort Near Area";
    if (lat > 6.700 && lat < 6.720 && lng > 80.050 && lng < 80.070) return "Horana City";
    if (lat > 6.780 && lat < 6.810 && lng > 80.040 && lng < 80.060) return "Thalagala Junction";
    
    return "Station near ${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}";
  }

  String _getEndStationName() {
    if (_routeName.contains('➔')) return _routeName.split('➔').last.trim();
    if (_routeName.contains(' - ')) return _routeName.split(' - ').last.trim();
    if (_routeName.contains(' to ')) return _routeName.split(' to ').last.trim();
    return "Route Destination";
  }
}

class _RevenueHistoryContent extends StatefulWidget {
  final String busNumber;
  final ScrollController scrollController;
  const _RevenueHistoryContent({required this.busNumber, required this.scrollController});
  @override
  _RevenueHistoryContentState createState() => _RevenueHistoryContentState();
}

class _RevenueHistoryContentState extends State<_RevenueHistoryContent> {
  final GlobalKey _reportKey = GlobalKey();

  Future<void> _generateMonthlyReport(Map<String, List<Map<String, dynamic>>> grouped) async {
    final total = grouped.values.expand((x) => x).fold(0.0, (sum, tx) {
      try { return sum + ((tx['amount'] as num?)?.toDouble() ?? 0.0); } catch (_) { return sum; }
    });
    final l10n = AppLocalizations.of(context)!;
    final dateStr = DateTime.now().toString().split(' ')[0];
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: RepaintBoundary(
          key: _reportKey,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_bus_rounded, size: 48, color: Color(0xFF2563EB)),
                const SizedBox(height: 16),
                Text(l10n.translate('monthly_revenue_report'), style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                Text('${l10n.translate('bus_label')} ${widget.busNumber}', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600])),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Text(l10n.translate('total_earned'), style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600])),
                      const SizedBox(height: 4),
                      Text('Rs. ${total.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(l10n.translate('generated_on', args: {'date': dateStr}), style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[400])),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.translate('cancel'))),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                RenderRepaintBoundary boundary = _reportKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
                ui.Image image = await boundary.toImage(pixelRatio: 3.0);
                final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                final pngBytes = byteData!.buffer.asUint8List();
                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/Revenue_Report_${widget.busNumber}.png');
                await file.writeAsBytes(pngBytes);
                // Share.shareXFiles([XFile(file.path)], text: 'Monthly Revenue Report for Bus ${widget.busNumber}');
              } catch (e) {
                debugPrint('Export error: $e');
              }
            },
            icon: const Icon(Icons.download_rounded),
            label: Text(l10n.translate('export_image')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.translate('revenue_history'), style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.getRevenueHistoryStream(widget.busNumber),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data ?? [];
                if (list.isEmpty) {
                  return Center(child: Text(l10n.translate('no_history')));
                }
                
                // Group by date (YYYY-MM-DD)
                final Map<String, List<Map<String, dynamic>>> grouped = {};
                for (final tx in list) {
                  final date = DateTime.parse(tx['created_at']).toLocal();
                  final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
                  if (!grouped.containsKey(dateStr)) grouped[dateStr] = [];
                  grouped[dateStr]!.add(tx);
                }
                
                final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: widget.scrollController,
                        itemCount: sortedDates.length,
                        itemBuilder: (context, i) {
                          final dateStr = sortedDates[i];
                          final dayTx = grouped[dateStr]!;
                          final totalDay = dayTx.fold(0.0, (sum, tx) => sum + (tx['amount'] as num).toDouble());
                          final dateObj = DateTime.parse(dateStr);
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!)),
                            child: Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                title: Text(dateStr, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: Text('Total: Rs. ${totalDay.toStringAsFixed(0)} • ${dayTx.length} trips', style: GoogleFonts.inter(color: const Color(0xFF10B981), fontWeight: FontWeight.w600)),
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () async {
                                        await SupabaseService.deleteDayRevenue(widget.busNumber, dateObj);
                                      },
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 16),
                                      label: Text('Delete Day', style: GoogleFonts.inter(color: Colors.red, fontSize: 12)),
                                    )
                                  ),
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: dayTx.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (context, j) {
                                      final tx = dayTx[j];
                                      final amt = (tx['amount'] as num).toDouble();
                                      final tDate = DateTime.parse(tx['created_at']).toLocal();
                                      final pId = tx['passenger_id'];
                                      final titleText = pId == null 
                                          ? "Manual Payment" 
                                          : "Passenger #${pId.toString().substring(0, 8)}";

                                      return ListTile(
                                        dense: true,
                                        leading: Icon(
                                          pId == null ? Icons.payments_outlined : Icons.person_outline_rounded,
                                          size: 18,
                                          color: Colors.grey[600],
                                        ),
                                        title: Text(titleText, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                        subtitle: Text("${tDate.hour.toString().padLeft(2, '0')}:${tDate.minute.toString().padLeft(2, '0')}", style: GoogleFonts.inter(fontSize: 12)),
                                        trailing: Text('Rs. ${amt.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _generateMonthlyReport(grouped),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFF0F172A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.insert_chart_rounded, color: Colors.white),
                        label: Text('Generate Monthly Report', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Problem Selection Bottom Sheet ───────────────────────────────────────────

class _ProblemSheetContent extends StatelessWidget {
  final String currentCode;
  const _ProblemSheetContent({required this.currentCode});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(child: Container(
            width: 40, height: 5,
            decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(3)),
          )),
          const SizedBox(height: 20),

          // Header
          Row(children: [
            const Icon(Icons.report_problem_rounded, color: Color(0xFFF59E0B), size: 22),
            const SizedBox(width: 10),
            Text(l10n.translate('what_is_problem'), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
          ]),
          const SizedBox(height: 6),
          Text(
            l10n.translate('select_issue_msg'),
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 20),

          // Problem options grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _problemOptions.length,
            itemBuilder: (context, i) {
              final opt = _problemOptions[i];
              final isActive = opt.code == currentCode;
              return GestureDetector(
                onTap: () => Navigator.pop(context, opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive ? opt.color : opt.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: opt.color.withValues(alpha: isActive ? 1 : 0.3), width: isActive ? 2 : 1),
                  ),
                  child: Row(children: [
                    Text(opt.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      l10n.translate(opt.code),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isActive ? Colors.white : opt.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // Cancel / Clear buttons
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.translate('cancel'), style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
              ),
            ),
            if (currentCode != 'on_time') ...[
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  // returning null signals "I want to clear the problem"
                  // We reuse the current option passed back to the parent which toggles it
                  onPressed: () => Navigator.pop(context, _problemOptions.firstWhere((o) => o.code == currentCode)),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(l10n.translate('clear_problem')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

// ── QR Scanner Dialog ────────────────────────────────────────────────────────

class _QRScannerDialog extends StatefulWidget {
  const _QRScannerDialog();
  @override
  _QRScannerDialogState createState() => _QRScannerDialogState();
}

class _QRScannerDialogState extends State<_QRScannerDialog> {
  final MobileScannerController _ctrl = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _closed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Passenger QR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.black, 
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: (capture) {
              if (_closed) return;
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final code = barcodes.first.rawValue;
                if (code != null && mounted) {
                  _closed = true;
                  Navigator.of(context).pop(code);
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF2563EB), width: 3),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Stack(
                children: [
                  Positioned(top: 20, left: 20, child: Container(width: 20, height: 2, color: Colors.white54)),
                  Positioned(top: 20, left: 20, child: Container(width: 2, height: 20, color: Colors.white54)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 60, left: 0, right: 0,
            child: Text(
              'Align QR code within the frame', 
              textAlign: TextAlign.center, 
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)
            ),
          )
        ],
      ),
    );
  }
}
