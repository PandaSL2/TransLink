import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/directions_service.dart';
import '../../models/bus_models.dart';

/// Bottom sheet shown when user taps "View Live Board" on a bus stop card.
/// Fetches transit routes that pass through this stop using Google Directions API.
class TLLiveBoardSheet extends StatefulWidget {
  final NearestBusStop stop;

  const TLLiveBoardSheet({super.key, required this.stop});

  static Future<void> show(BuildContext context, NearestBusStop stop) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TLLiveBoardSheet(stop: stop),
    );
  }

  @override
  State<TLLiveBoardSheet> createState() => _TLLiveBoardSheetState();
}

class _TLLiveBoardSheetState extends State<TLLiveBoardSheet>
    with SingleTickerProviderStateMixin {
  final _service = DirectionsService();

  List<_RouteInfo> _routes = [];
  bool _loading = true;
  String? _error;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _fetchRoutes();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRoutes() async {
    setState(() { _loading = true; _error = null; });

    try {
      // Use multiple common Sri Lanka landmark destinations to extract diverse routes
      final landmarks = [
        // Colombo Fort (lat, lng)
        (6.9355, 79.8503),
        // Maharagama (lat, lng)
        (6.8480, 79.9260),
        // Kandy (lat, lng)
        (7.2906, 80.6337),
      ];

      final seen = <String>{};
      final routes = <_RouteInfo>[];

      for (final dest in landmarks) {
        if (routes.length >= 6) break; // enough routes
        try {
          final results = await _service.getTransitRoute(
            widget.stop.lat, widget.stop.lng,
            dest.$1, dest.$2,
          );
          for (final r in results) {
            // CRUCIAL FIX: Only take the very FIRST bus segment of the entire trip.
            // If the route goes Thalagala -> Kottawa (129) -> Galle (EX1), we ONLY
            // want to show 129 because that's the only one at THIS stop.
            final firstBusSeg = r.segments.where((s) => s.type == SegmentType.bus).firstOrNull;
            
            if (firstBusSeg != null && firstBusSeg.routeNumber != null) {
              final key = firstBusSeg.routeNumber!;
              if (!seen.contains(key)) {
                seen.add(key);
                
                // Calculate accurate ETA based on actual Google Maps departure time
                int eta = firstBusSeg.durationMin; // Fallback if no departure time
                if (firstBusSeg.departureTimeSeconds != null) {
                  final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                  eta = (firstBusSeg.departureTimeSeconds! - nowSecs) ~/ 60;
                  if (eta < 0) eta = 0; // If it's already departing, show 0 (Due)
                }

                routes.add(_RouteInfo(
                  routeNumber: key,
                  headsign: firstBusSeg.headsign ?? firstBusSeg.arrivalStop ?? 'Via this stop',
                  operator: firstBusSeg.operator,
                  etaMin: eta,
                  departureTimeText: firstBusSeg.departureTimeText,
                ));
              }
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _routes = routes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load live data'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.departure_board_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.stop.name,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${widget.stop.walkingMeters}m · ${widget.stop.walkingMinutes} min walk',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Live indicator
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Opacity(
                    opacity: _pulseAnim.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.liveGreen.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.circle, color: AppColors.liveGreen, size: 7),
                          const SizedBox(width: 5),
                          Text(
                            'LIVE',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.liveGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 24, color: Theme.of(context).dividerColor),

          // ── Route List ───────────────────────────────────────────
          Flexible(
            child: _loading
                ? _buildLoading()
                : _error != null
                    ? _buildError()
                    : _routes.isEmpty
                        ? _buildEmpty()
                        : _buildRouteList(isDark),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text(
            'Loading routes...',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _fetchRoutes,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus_rounded, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            'No bus routes found near this stop',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteList(bool isDark) {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _routes.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: Theme.of(context).dividerColor.withOpacity(0.5),
      ),
      itemBuilder: (context, i) {
        final route = _routes[i];
        return _RouteRow(route: route, pulse: _pulseAnim);
      },
    );
  }
}

class _RouteInfo {
  final String routeNumber;
  final String headsign;
  final String? operator;
  final int etaMin;
  final String? departureTimeText;

  const _RouteInfo({
    required this.routeNumber,
    required this.headsign,
    this.operator,
    required this.etaMin,
    this.departureTimeText,
  });
}

class _RouteRow extends StatelessWidget {
  final _RouteInfo route;
  final Animation<double> pulse;

  const _RouteRow({required this.route, required this.pulse});

  @override
  Widget build(BuildContext context) {
    // Determine if CTB or Private based on route number convention
    final isCTB = route.operator?.toLowerCase().contains('ctb') == true ||
        route.operator?.toLowerCase().contains('sri lanka') == true;
    final badgeColor = isCTB ? AppColors.ctbRed : AppColors.privateBlue;
    final badgeBg = isCTB ? const Color(0xFFFFEBEE) : const Color(0xFFE3F2FD);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          // Route number badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: badgeColor.withOpacity(0.3)),
            ),
            child: Text(
              route.routeNumber,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: badgeColor,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Headsign & operator
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.headsign,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (route.operator != null)
                  Text(
                    route.operator!,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),

          // Duration
          AnimatedBuilder(
            animation: pulse,
            builder: (_, __) => Opacity(
              opacity: pulse.value,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.liveGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 11, color: AppColors.liveGreen),
                    const SizedBox(width: 4),
                    Text(
                      route.etaMin == 0 ? 'Due' : '~${route.etaMin} min',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.liveGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
