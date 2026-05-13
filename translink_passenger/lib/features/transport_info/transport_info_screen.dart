import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../models/bus_models.dart';
import '../../core/utils/app_localizations.dart';
import '../../services/supabase_service.dart';
import '../../services/timetable_service.dart';

class TransportInfoScreen extends StatefulWidget {
  final RouteModel route;
  final RouteVariantModel variant;
  const TransportInfoScreen({super.key, required this.route, required this.variant});

  @override
  State<TransportInfoScreen> createState() => _TransportInfoScreenState();
}

class _TransportInfoScreenState extends State<TransportInfoScreen> {
  List<RouteStopSequenceModel> _stops = [];
  List<DateTime> _nextDepartures = [];
  bool _loading = true;
  int _highlightedStopIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final now = DateTime.now();
    const isHoliday = false;
    final dayType = TimetableService.getDayType(now, isHoliday: isHoliday);

    final sequences = await SupabaseService.getRouteStopSequences(widget.variant.id);
    final profiles = await SupabaseService.getServiceProfiles(widget.route.id);
    final fixed = await SupabaseService.getFixedDepartures(widget.variant.id, dayType);

    final matchProfiles = profiles.where((p) => p.dayType == dayType || p.dayType == 'all').toList();
    final departures = TimetableService.generateDepartureTimes(
      profiles: matchProfiles,
      fixedDepartures: fixed,
      date: now,
    );
    final upcoming = TimetableService.getUpcoming(allDepartures: departures, count: 1);
    final delay = matchProfiles.isNotEmpty ? matchProfiles.first.delayFactorMinutes : 5;

    int currentIdx = 0;
    if (upcoming.isNotEmpty) {
      final dep = upcoming.first;
      for (int i = 0; i < sequences.length; i++) {
        final eta = TimetableService.etaForStop(
          departureTime: dep,
          travelTimeFromOriginMinutes: sequences[i].travelTimeFromOriginMinutes,
          delayFactorMinutes: delay,
        );
        if (eta > 0) { currentIdx = i; break; }
      }
    }

    if (mounted) {
      setState(() {
        _stops = sequences;
        _nextDepartures = upcoming;
        _highlightedStopIndex = currentIdx;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('${AppLocalizations.of(context)!.translate('route_text')} ${widget.route.routeNumber}'),
        leading: const BackButton(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.secondary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, const Color(0xFF1D4ED8)]),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${AppLocalizations.of(context)!.translate('route_text')} ${widget.route.routeNumber}', style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                          Text(widget.route.name, style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        ]),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(AppLocalizations.of(context)!.translate('bus_label'), style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(AppLocalizations.of(context)!.translate('from_label'), style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.65), fontSize: 11)),
                          Text(widget.variant.originName, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 18),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(AppLocalizations.of(context)!.translate('to_label'), style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.65), fontSize: 11)),
                          Text(widget.variant.destinationName, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.right),
                        ]),
                      ),
                    ]),
                    if (_nextDepartures.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          const Icon(Icons.schedule_rounded, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${AppLocalizations.of(context)!.translate('next_departure')}: ${DateFormat('hh:mm a').format(_nextDepartures.first)}',
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 24),

                Text(AppLocalizations.of(context)!.translate('stop_timeline'), style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Theme.of(context).textTheme.bodyLarge?.color)),
                const SizedBox(height: 16),
                if (_stops.isEmpty)
                  Center(child: Text(AppLocalizations.of(context)!.translate('no_stops_available')))
                else
                  ...List.generate(_stops.length, (i) => _stopTimelineTile(i)),
              ]),
            ),
    );
  }

  Widget _stopTimelineTile(int index) {
    final seq = _stops[index];
    final stop = seq.stop;
    final isCurrent = index == _highlightedStopIndex;
    final isPassed = index < _highlightedStopIndex;
    final isLast = index == _stops.length - 1;
    final isFirst = index == 0;

    DateTime? eta;
    if (_nextDepartures.isNotEmpty) {
      eta = _nextDepartures.first.add(Duration(minutes: seq.travelTimeFromOriginMinutes + 5));
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          SizedBox(
            width: 36,
            child: Column(
              children: [
                if (!isFirst)
                  Expanded(child: Center(
                    child: Container(width: 2, color: isPassed ? AppColors.secondary : Theme.of(context).dividerColor),
                  )),
                Container(
                  width: isCurrent ? 14 : 10,
                  height: isCurrent ? 14 : 10,
                  decoration: BoxDecoration(
                    color: isCurrent ? AppColors.secondary : (isPassed ? AppColors.secondary.withValues(alpha: 0.4) : Theme.of(context).dividerColor),
                    shape: BoxShape.circle,
                    border: isCurrent ? Border.all(color: AppColors.secondary.withValues(alpha: 0.3), width: 3) : null,
                  ),
                ),
                if (!isLast)
                  Expanded(child: Center(
                    child: Container(width: 2, color: isPassed ? AppColors.secondary : Theme.of(context).dividerColor),
                  )),
              ],
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (stop != null)
                        Text(stop.name, style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isCurrent ? AppColors.secondary : (isPassed ? Theme.of(context).textTheme.bodySmall?.color : Theme.of(context).textTheme.bodyLarge?.color),
                        ))
                      else
                        Text('${AppLocalizations.of(context)!.translate('stop_prefix')} #${seq.sequenceOrder}', style: GoogleFonts.inter(fontSize: 14)),
                      if (eta != null)
                        Text(
                          isPassed ? AppLocalizations.of(context)!.translate('passed_label') : '${AppLocalizations.of(context)!.translate('today_label')} / ${DateFormat('HH:mm').format(eta)}',
                          style: GoogleFonts.inter(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                    ]),
                  ),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.directions_bus_rounded, color: AppColors.secondary, size: 13),
                        const SizedBox(width: 4),
                        Text(AppLocalizations.of(context)!.translate('current_label'), style: GoogleFonts.inter(color: AppColors.secondary, fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}