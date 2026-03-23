import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../models/bus_models.dart';
import '../../services/supabase_service.dart';
import '../../services/timetable_service.dart';
import '../../services/holiday_service.dart';
import '../../core/utils/app_localizations.dart';

class BusStopScreen extends StatefulWidget {
  final StopModel stop;
  const BusStopScreen({super.key, required this.stop});

  @override
  State<BusStopScreen> createState() => _BusStopScreenState();
}

class _BusStopScreenState extends State<BusStopScreen> {
  List<ArrivalInfo> _arrivals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadArrivals();
  }

  Future<void> _loadArrivals() async {
    try {
      final now = DateTime.now();
      final isHoliday = HolidayService().isHoliday(now);
      final dayType = TimetableService.getDayType(now, isHoliday: isHoliday);

      final routes = await SupabaseService.getActiveRoutes();
      final arrivals = <ArrivalInfo>[];

      for (final route in routes) {
        final variants = await SupabaseService.getRouteVariants(route.id);
        for (final variant in variants) {

          final sequences = await SupabaseService.getRouteStopSequences(variant.id);
          final seq = sequences.cast<RouteStopSequenceModel?>().firstWhere(
            (s) => s?.stopId == widget.stop.id,
            orElse: () => null,
          );
          if (seq == null) continue;

          final profiles = await SupabaseService.getServiceProfiles(route.id);
          final fixed = await SupabaseService.getFixedDepartures(variant.id, dayType);
          final matchingProfiles = profiles.where(
            (p) => p.dayType == dayType || p.dayType == 'all',
          ).toList();

          final departures = TimetableService.generateDepartureTimes(
            profiles: matchingProfiles,
            fixedDepartures: fixed,
            date: now,
          );

          final upcoming = TimetableService.getUpcoming(allDepartures: departures, count: 3);
          final delay = profiles.isNotEmpty ? profiles.first.delayFactorMinutes : 5;

          for (final dep in upcoming) {
            final eta = TimetableService.etaForStop(
              departureTime: dep,
              travelTimeFromOriginMinutes: seq.travelTimeFromOriginMinutes,
              delayFactorMinutes: delay,
            );
            if (eta < 0) continue;

            arrivals.add(ArrivalInfo(
              busId: route.routeNumber,
              routeNumber: route.routeNumber,
              destination: variant.destinationName,
              etaMinutes: eta,
              status: eta <= 0 ? 'on_time' : (delay > 8 ? 'delayed' : 'on_time'),
            ));
          }
        }
      }

      arrivals.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
      if (mounted) setState(() { _arrivals = arrivals; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.stop.name),
        leading: const BackButton(),
        actions: [
          IconButton(icon: const Icon(Icons.favorite_border_rounded), onPressed: () {}),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async { setState(() => _loading = true); await _loadArrivals(); },
        color: AppColors.secondary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.place_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.stop.name, style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                      if (widget.stop.address != null)
                        Text(widget.stop.address!, style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                    ]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(l10n.translate('upcoming_arrivals'), style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Theme.of(context).textTheme.bodyLarge?.color), overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(l10n.translate('live'), style: GoogleFonts.inter(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.secondary)))
            else if (_arrivals.isEmpty)
              _emptyState()
            else
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  children: [

                    _tableHeader(l10n),
                    Divider(height: 1, color: Theme.of(context).dividerColor),

                    ..._arrivals.map((a) => _arrivalRow(a, l10n)),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.map_rounded, size: 20),
                label: Text(l10n.translate('show_on_map')),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tableHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _headerCell(l10n.translate('route_prefix'), flex: 1),
          _headerCell(l10n.translate('to_label'), flex: 3),
          _headerCell(l10n.translate('eta_label'), flex: 2),
          _headerCell(l10n.translate('status_label'), flex: 2),
        ],
      ),
    );
  }

  Widget _headerCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodySmall?.color)),
    );
  }

  Widget _arrivalRow(ArrivalInfo a, AppLocalizations l10n) {
    return Column(
      children: [
        Divider(height: 1, color: Theme.of(context).dividerColor),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(a.busId, style: GoogleFonts.inter(color: AppColors.secondary, fontSize: 12, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(a.destination, style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  a.etaMinutes == 0 ? l10n.translate('now_label') : '${a.etaMinutes} ${l10n.translate('min')}',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: a.etaMinutes <= 2 ? AppColors.accent : Theme.of(context).textTheme.bodyLarge?.color),
                ),
              ),
              Expanded(
                flex: 2,
                child: _statusPill(a.status, l10n),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusPill(String status, AppLocalizations l10n) {
    Color bg, fg;
    String label;
    switch (status) {
      case 'delayed':
        bg = AppColors.secondary.withValues(alpha: 0.15); fg = AppColors.secondary; label = l10n.translate('delayed');
        break;
      case 'cancelled':
        bg = AppColors.error.withValues(alpha: 0.15); fg = AppColors.error; label = l10n.translate('cancelled');
        break;
      default:
        bg = AppColors.accent.withValues(alpha: 0.15); fg = AppColors.accent; label = l10n.translate('on_time');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, style: GoogleFonts.inter(color: fg, fontSize: 10, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _emptyState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(Icons.directions_bus_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 48),
          const SizedBox(height: 12),
          Text(l10n.translate('no_upcoming_buses'), style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
        ]),
      ),
    );
  }
}
class ArrivalInfo {
  final String busId;
  final String routeNumber;
  final String destination;
  final int etaMinutes;
  final String status;

  ArrivalInfo({
    required this.busId,
    required this.routeNumber,
    required this.destination,
    required this.etaMinutes,
    required this.status,
  });
}