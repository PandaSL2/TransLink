import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_localizations.dart';
import '../../core/services/directions_service.dart';
import '../../services/location_service.dart';
import '../map/place_search_screen.dart';
import '../../core/services/settings_provider.dart';
import '../../ui/main_shell.dart';
import '../../models/bus_models.dart';
import '../ai/ai_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _directionsService = DirectionsService();
  final _locationService = LocationService();
  List<NearestBusStop> _nearbyStops = [];
  bool _isLoadingStops = true;

  @override
  void initState() {
    super.initState();
    _loadNearbyStops();
  }

  Future<void> _loadNearbyStops() async {
    final cachedPos = _locationService.lastPosition;
    if (cachedPos != null && _nearbyStops.isEmpty) {
      final stops = await _directionsService.findNearbyBusStops(cachedPos.lat, cachedPos.lng);
      if (mounted) setState(() { _nearbyStops = stops; _isLoadingStops = false; });
    }

    try {
      final pos = await _locationService.getCurrentLocation();
      if (pos != null) {
        final stops = await _directionsService.findNearbyBusStops(pos.lat, pos.lng);
        if (mounted) setState(() { _nearbyStops = stops; });
      }
    } catch (e) {
      debugPrint('Error loading nearby stops: $e');
    } finally {
      if (mounted) setState(() => _isLoadingStops = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(l10n),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchCard(l10n),
                  const SizedBox(height: 32),
                  _buildSectionHeader(l10n.translate('nearby_stops') ?? 'Nearby Bus Stops', () {
                    final shell = context.findAncestorStateOfType<MainShellState>();
                    if (shell != null) shell.setTab(2);
                  }),
                  const SizedBox(height: 16),
                  _buildNearbyStopsList(),
                  const SizedBox(height: 32),
                  _buildSectionHeader(l10n.translate('quick_actions') ?? 'Quick Actions', null),
                  const SizedBox(height: 16),
                  _buildQuickActions(l10n),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(AppLocalizations l10n) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        title: Text(
          'TransLink',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w900, 
            fontSize: 28, 
            color: Theme.of(context).colorScheme.onSurface,
            letterSpacing: -1,
          ),
        ),
        background: Container(color: Theme.of(context).scaffoldBackgroundColor),
      ),
      actions: [
        Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.8),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, 
                  color: Theme.of(context).colorScheme.primary, size: 20),
                onPressed: () => settings.toggleTheme(),
              ),
            );
          },
        ),
        PopupMenuButton<String>(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.language_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
          ),
          color: Theme.of(context).cardColor,
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (lang) {
            final settings = Provider.of<SettingsProvider>(context, listen: false);
            settings.setLanguage(lang);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'English', child: Text('English')),
            const PopupMenuItem(value: 'සිංහල', child: Text('සිංහල')),
            const PopupMenuItem(value: 'தமிழ்', child: Text('தமிழ்')),
          ],
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildSearchCard(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () async {
        final res = await Navigator.push(context, MaterialPageRoute(builder: (c) => const PlaceSearchScreen()));
        if (res is TripModel && mounted) {
           final shell = context.findAncestorStateOfType<MainShellState>();
           if (shell != null) shell.setTab(1, argument: res);
        }
      },
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.4 : 0.08), 
              blurRadius: 25, 
              offset: const Offset(0, 10)
            ),
          ],
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.secondary, size: 26),
            const SizedBox(width: 16),
            Text(
              l10n.translate('search_hint') ?? 'Where are you going?',
              style: GoogleFonts.inter(
                fontSize: 16, 
                fontWeight: FontWeight.w600, 
                color: Theme.of(context).colorScheme.onSurfaceVariant
              ),
            ),
            const Spacer(),
            Icon(Icons.tune_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback? onSeeAll) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text(
              AppLocalizations.of(context)?.translate('see_all') ?? 'See All',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.secondary),
            ),
          ),
      ],
    );
  }

  Widget _buildNearbyStopsList() {
    if (_isLoadingStops) {
      return SizedBox(
        height: 140,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          itemBuilder: (_, _) => _buildStopSkeleton(),
        ),
      );
    }

    if (_nearbyStops.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, 
          borderRadius: BorderRadius.circular(24), 
          border: Border.all(color: Theme.of(context).dividerColor)
        ),
        child: Center(child: Text('No bus stops found nearby.', style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
      );
    }

    return SizedBox(
      height: 155,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _nearbyStops.length,
        itemBuilder: (context, i) => _buildStopCard(_nearbyStops[i]),
      ),
    );
  }

  Widget _buildStopCard(NearestBusStop stop) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        final shell = context.findAncestorStateOfType<MainShellState>();
        if (shell != null) {
          shell.setTab(1, argument: TripModel(
            destinationName: stop.name,
            destLat: stop.lat,
            destLng: stop.lng,
          ));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: MediaQuery.of(context).size.width * 0.68,
        margin: const EdgeInsets.only(right: 20, bottom: 12, top: 4),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.06), 
              blurRadius: 20, 
              offset: const Offset(0, 10)
            )
          ],
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, Color(0xFF1D4ED8)], 
                      begin: Alignment.topLeft, 
                      end: Alignment.bottomRight
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.departure_board_rounded, color: Colors.white, size: 24),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '${stop.walkingMinutes} min',
                    style: GoogleFonts.inter(
                      fontSize: 12, 
                      fontWeight: FontWeight.w900, 
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 0.5
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              stop.name, 
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: -0.5), 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.directions_walk_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '${stop.walkingMeters}m from you', 
                  style: GoogleFonts.inter(
                    fontSize: 13, 
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  )
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopSkeleton() {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 20, bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(28),
      ),
    );
  }

  Widget _buildQuickActions(AppLocalizations l10n) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _quickActionBtn(Icons.account_balance_wallet_rounded, l10n.translate('top_up'), Colors.orange, () {
            final shell = context.findAncestorStateOfType<MainShellState>();
            if (shell != null) shell.setTab(3);
          }),
          const SizedBox(width: 16),
          _quickActionBtn(Icons.auto_awesome_rounded, l10n.translate('ai_support'), Colors.purple, () {
            Navigator.push(context, MaterialPageRoute(builder: (c) => const AiChatScreen()));
          }),
          const SizedBox(width: 16),
          _quickActionBtn(Icons.map_rounded, l10n.translate('map_view'), Colors.teal, () {
            final shell = context.findAncestorStateOfType<MainShellState>();
            if (shell != null) shell.setTab(1);
          }),
        ],
      ),
    );
  }

  Widget _quickActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withOpacity(0.15), width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
