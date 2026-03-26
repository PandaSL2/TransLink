import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_handler.dart';
import '../../core/constants/driver_constants.dart';
import '../../services/route_schedule_service.dart';
import '../../services/schedule_watch_service.dart';
import '../../services/supabase_service.dart';
import '../home/home_screen.dart';
import '../../core/utils/app_localizations.dart';
import '../../core/services/settings_provider.dart';
import 'package:provider/provider.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _busCtrl   = TextEditingController();
  final _routeCtrl = TextEditingController();
  String _selectedFleet = 'private';

  RouteSchedule? _selectedSchedule;
  bool _isRegistering = false;
  bool _isLoadingRoutes = true;

  List<Map<String, String>> _supabaseRoutes = [];
  List<Map<String, String>> _filteredRoutes = [];

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    try {
      final routes = await SupabaseService.getAvailableRoutes();
      if (mounted) {
        setState(() {
          _supabaseRoutes = routes;
          _filteredRoutes = routes;
          _isLoadingRoutes = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading routes: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Registration Failed'),
            content: Text(ErrorHandler.getFriendlyMessage(e, context)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Retry')),
            ],
          ),
        );
        setState(() => _isLoadingRoutes = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredRoutes = _supabaseRoutes;
      } else {
        _filteredRoutes = _supabaseRoutes.where((r) {
          final num = r['number']?.toLowerCase() ?? '';
          final name = r['name']?.toLowerCase() ?? '';
          final q = query.toLowerCase();
          return num.contains(q) || name.contains(q);
        }).toList();
      }

      final schedule = RouteScheduleService.getSchedule(query);
      _selectedSchedule = schedule;
    });
  }

  void _onRouteSelected(String number, String name) {
    _routeCtrl.text = number;
    final schedule = RouteScheduleService.getSchedule(number);
    setState(() {
      _selectedSchedule = schedule;
    });
  }

  Future<bool> _requestPermissions() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context)!;

      _showDialog(l10n.translate('location_permission_required'),
          l10n.translate('location_permission_msg'));
      return false;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context)!;

      _showDialog(l10n.translate('gps_is_off'), l10n.translate('gps_is_off_msg'));
      return false;
    }

    if (!kIsWeb) {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        if (!mounted) return false;
        final l10n = AppLocalizations.of(context)!;

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.translate('reliability_first'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            content: Text(
              l10n.translate('battery_optimization_msg'),
              style: GoogleFonts.inter(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.translate('ok_understand'))),
            ],
          ),
        );
        await Permission.ignoreBatteryOptimizations.request();
      }

      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }
    return true;
  }

  void _showDialog(String title, String msg) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text(msg, style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.translate('cancel'))),
          TextButton(
            onPressed: () { Navigator.pop(context); Geolocator.openAppSettings(); },
            child: Text(l10n.translate('open_settings')),
          ),
        ],
      ),
    );
  }

  Future<void> _register() async {
    final busNum   = _busCtrl.text.trim().toUpperCase();
    final routeNum = _routeCtrl.text.trim();

    if (busNum.isEmpty || routeNum.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('please_fill_all'))),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isRegistering = true);

    final granted = await _requestPermissions();
    if (!granted) {
      if (mounted) setState(() => _isRegistering = false);
      return;
    }

    final schedule = RouteScheduleService.getSchedule(routeNum);
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      prefs.setBool(  DriverConstants.keyIsLoggedIn,     true),
      prefs.setString(DriverConstants.keyBusNumber,      busNum),
      prefs.setString(DriverConstants.keyRouteNumber,    routeNum),
      prefs.setString(DriverConstants.keyRouteName,      schedule.label),
      prefs.setInt(   DriverConstants.keyHeadwayMinutes, schedule.headwayMinutes),
      prefs.setString(DriverConstants.keyScheduleLabel,  schedule.frequencyLabel),
      prefs.setString(DriverConstants.keyFirstBus,       schedule.firstBus),
      prefs.setString(DriverConstants.keyLastBus,        schedule.lastBus),
      prefs.setString(DriverConstants.keyFleetType,      _selectedFleet),
    ]);

    unawaited(ScheduleWatchService.registerPeriodicTask());
    await prefs.setBool(DriverConstants.keyIsTracking, false);

    if (mounted) {

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l10n.translate('driver_portal'), style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                    Text(l10n.translate('one_time_reg'), style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13)),
                  ]),
                ),

                _buildLanguageSelector(),
              ]),

              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    l10n.translate('register_once_msg'),
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1D4ED8)),
                  )),
                ]),
              ),

              const SizedBox(height: 28),

               _label(l10n.translate('select_fleet')),
               const SizedBox(height: 12),
               Row(
                 children: [
                   Expanded(
                     child: _fleetCard(
                       'ctb',
                       l10n.translate('ctb_label'),
                       Icons.account_balance_rounded,
                       const Color(0xFFD32F2F),
                     ),
                   ),
                   const SizedBox(width: 16),
                   Expanded(
                     child: _fleetCard(
                       'private',
                       l10n.translate('private_label'),
                       Icons.directions_bus_rounded,
                       const Color(0xFF1976D2),
                     ),
                   ),
                 ],
               ),

               const SizedBox(height: 24),

               _label(l10n.translate('bus_label')),
              const SizedBox(height: 8),
              TextField(
                controller: _busCtrl,
                textCapitalization: TextCapitalization.characters,
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                decoration: _inputDeco(l10n.translate('bus_number_hint')),
              ),

              const SizedBox(height: 24),

              _label(l10n.translate('route_label')),
              const SizedBox(height: 8),

              TextField(
                controller: _routeCtrl,
                onChanged: _onSearchChanged,
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: _inputDeco(l10n.translate('search_route_hint')).copyWith(
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2563EB)),
                ),
              ),

              const SizedBox(height: 12),

              if (_isLoadingRoutes)
                const Center(child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(),
                ))
              else if (_filteredRoutes.isEmpty && _routeCtrl.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      l10n.translate('no_matching_route'),
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF9A3412)),
                    )),
                  ]),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filteredRoutes.length > 5 && _routeCtrl.text.isEmpty ? 5 : _filteredRoutes.length,
                  itemBuilder: (ctx, i) {
                    final r = _filteredRoutes[i];
                    final isSelected = _routeCtrl.text == r['number'];
                    return GestureDetector(
                      onTap: () => _onRouteSelected(r['number']!, r['name']!),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF2563EB) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(child: Text(
                              r['number']!,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: isSelected ? Colors.white : const Color(0xFF2563EB),
                              ),
                            )),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Text(
                            r['name']!,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isSelected ? Colors.white : const Color(0xFF334155),
                            ),
                          )),
                          if (isSelected) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                        ]),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 12),

              if (_selectedSchedule != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded, color: Color(0xFF16A34A), size: 18),
                    const SizedBox(width: 10),
                    Text(
                      '${_selectedSchedule!.frequencyLabel}  ·  ${_selectedSchedule!.hoursLabel}',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF15803D)),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
              ] else ...[
                const SizedBox(height: 20),
              ],

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _isRegistering ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF93C5FD),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isRegistering
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.how_to_reg_rounded, size: 24),
                          const SizedBox(width: 10),
                          Text(l10n.translate('register'), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700)),
                        ]),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    final settings = Provider.of<SettingsProvider>(context);
    return PopupMenuButton<String>(
      onSelected: settings.setLanguage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.language_rounded, size: 18, color: Color(0xFF2563EB)),
          const SizedBox(width: 6),
          Text(settings.languageName, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
        ]),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'English', child: Text('English')),
        const PopupMenuItem(value: 'සිංහල', child: Text('සිංහල')),
        const PopupMenuItem(value: 'தமிழ்', child: Text('தமிழ்')),
      ],
    );
  }

  Widget _label(String text) =>
    Text(text, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF475569)));

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(color: const Color(0xFFCBD5E1)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );

  Widget _fleetCard(String type, String label, IconData icon, Color color) {
    final isSelected = _selectedFleet == type;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedFleet = type);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE2E8F0),
            width: 2,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))
          ] : null,
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : color, size: 30),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}