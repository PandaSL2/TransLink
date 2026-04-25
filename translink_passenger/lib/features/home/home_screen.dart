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
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _directionsService = DirectionsService();
  final _locationService = LocationService();
  final SpeechToText _speech = SpeechToText();
  
  List<NearestBusStop> _nearbyStops = [];
  List<Map<String, String>> _intercityRoutes = [];
  Set<String> _favoriteIntercity = {};
  
  bool _isLoadingStops = true;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadIntercityRoutes();
    _loadNearbyStops();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList('favorite_intercity') ?? [];
    if (mounted) setState(() => _favoriteIntercity = favs.toSet());
  }

  Future<void> _loadIntercityRoutes() async {
    final l10n = AppLocalizations.of(context);
    final routes = [
      {'num': 'EX 01', 'name': l10n?.translate('colombo_matara') ?? 'Colombo - Matara', 'price': '1,200'},
      {'num': 'EX 02', 'name': l10n?.translate('colombo_galle') ?? 'Colombo - Galle', 'price': '950'},
      {'num': 'EX 05', 'name': l10n?.translate('kaduwela_matara') ?? 'Kaduwela - Matara', 'price': '1,450'},
      {'num': 'EX 08', 'name': l10n?.translate('makumbura_galle') ?? 'Makumbura - Galle', 'price': '850'},
      {'num': 'EX 12', 'name': l10n?.translate('colombo_kandy') ?? 'Colombo - Kandy', 'price': '1,100'},
    ];
    
    if (mounted) setState(() => _intercityRoutes = routes);
  }

  Future<void> _toggleFavorite(String routeNum) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteIntercity.contains(routeNum)) {
        _favoriteIntercity.remove(routeNum);
      } else {
        _favoriteIntercity.add(routeNum);
      }
    });
    await prefs.setStringList('favorite_intercity', _favoriteIntercity.toList());
  }

  void _startListening() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)?.translate('mic_permission_required') ?? 'Microphone permission required'))
        );
      }
      return;
    }

    try {
      bool available = await _speech.initialize(
        onError: (val) => setState(() => _isListening = false),
        onStatus: (val) => debugPrint('Speech status: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(onResult: (result) {
          if (result.finalResult) {
            setState(() => _isListening = false);
            _navigateToSearch(query: result.recognizedWords);
          }
        });
      }
    } catch (e) {
      debugPrint('Voice search error: $e');
      setState(() => _isListening = false);
    }
  }

  void _navigateToSearch({String? query}) async {
    final res = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (c) => PlaceSearchScreen(initialQuery: query))
    );
    if (res is TripModel && mounted) {
       final shell = context.findAncestorStateOfType<MainShellState>();
       if (shell != null) shell.setTab(1, argument: res);
    }
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
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(l10n),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _buildSearchCard(l10n),
                  const SizedBox(height: 24),
                  _buildFleetStatus(l10n),
                  const SizedBox(height: 32),
                  _buildSectionHeader(l10n.translate('intercity_express') ?? 'Intercity Express', null, l10n),
                  const SizedBox(height: 16),
                  _buildIntercityList(l10n),
                  const SizedBox(height: 32),
                  _buildSectionHeader(l10n.translate('nearby_stops') ?? 'Nearby Bus Stops', () {
                    final shell = context.findAncestorStateOfType<MainShellState>();
                    if (shell != null) shell.setTab(2);
                  }, l10n),
                  const SizedBox(height: 16),
                  _buildNearbyStopsList(l10n),
                  const SizedBox(height: 32),
                  _buildSectionHeader(l10n.translate('quick_actions') ?? 'Quick Actions', null, l10n),
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
      expandedHeight: 100,
      floating: false,
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        title: Row(
          children: [
            Text(
              'TransLink',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900, 
                fontSize: 24, 
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(width: 8),
          ],
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, 
                  color: Theme.of(context).colorScheme.onSurface, size: 20),
                onPressed: () => settings.toggleTheme(),
              ),
            );
          },
        ),
        _buildLanguageAction(),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildLanguageAction() {
    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.language_rounded, color: Theme.of(context).colorScheme.onSurface, size: 20),
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
    );
  }

  Widget _buildSearchCard(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _navigateToSearch(),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), 
              blurRadius: 20, 
              offset: const Offset(0, 8)
            ),
          ],
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(width: 16),
            Text(
              l10n.translate('search_hint') ?? 'Where are you going?',
              style: GoogleFonts.inter(
                fontSize: 16, 
                fontWeight: FontWeight.w600, 
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)
              ),
            ),
            const Spacer(),
            VerticalDivider(indent: 18, endIndent: 18, color: Theme.of(context).dividerColor),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                _isListening ? Icons.graphic_eq_rounded : Icons.mic_none_rounded, 
                color: _isListening ? Colors.redAccent : Theme.of(context).colorScheme.primary, 
                size: 22
              ),
              onPressed: _startListening,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFleetStatus(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.1), AppColors.primary.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.translate('fleet_status') ?? 'Fleet Status',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Colors.green, size: 6),
                    const SizedBox(width: 6),
                    Text(
                      'LIVE',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _fleetStatItem(l10n.translate('ctb_label') ?? 'CTB', '42', AppColors.ctbRed, l10n),
              const SizedBox(width: 32),
              _fleetStatItem(l10n.translate('private_label') ?? 'Private', '186', AppColors.privateBlue, l10n),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fleetStatItem(String label, String count, Color color, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color),
        ),
        Text(
          count,
          style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
        ),
        Text(
          l10n.translate('active_buses') ?? 'Active Buses',
          style: GoogleFonts.inter(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildIntercityList(AppLocalizations l10n) {
    if (_intercityRoutes.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _intercityRoutes.length,
        itemBuilder: (context, i) {
          final r = _intercityRoutes[i];
          final isFav = _favoriteIntercity.contains(r['num']);
          
          return GestureDetector(
            onTap: () => _navigateToSearch(query: r['name']),
            child: Container(
              width: 200,
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          r['num']!,
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.secondary),
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: Icon(isFav ? Icons.star_rounded : Icons.star_border_rounded, 
                          color: isFav ? Colors.amber : Colors.grey[400], size: 20),
                        onPressed: () => _toggleFavorite(r['num']!),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    r['name']!,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.translate('starting_from_rs') ?? 'Starting from Rs.'}${r['price']}',
                    style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback? onSeeAll, AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.2),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text(
              AppLocalizations.of(context)?.translate('see_all') ?? 'See All',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
            ),
          ),
      ],
    );
  }

  Widget _buildNearbyStopsList(AppLocalizations l10n) {
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
        child: Center(child: Text(l10n.translate('no_stops_found') ?? 'No bus stops found nearby.', style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
      );
    }

    return SizedBox(
      height: 155,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _nearbyStops.length,
        itemBuilder: (context, i) => _buildStopCard(_nearbyStops[i], l10n),
      ),
    );
  }

  Widget _buildStopCard(NearestBusStop stop, AppLocalizations l10n) {
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
        width: 260,
        margin: const EdgeInsets.only(right: 16, bottom: 8, top: 4),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.4 : 0.04), 
              blurRadius: 15, 
              offset: const Offset(0, 6)
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.departure_board_rounded, color: AppColors.primary, size: 20),
                ),
                const Spacer(),
                Text(
                  '${stop.walkingMinutes} ${l10n.translate('min') ?? 'min'}',
                  style: GoogleFonts.inter(
                    fontSize: 12, 
                    fontWeight: FontWeight.w900, 
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              stop.name, 
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 17), 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.directions_walk_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '${stop.walkingMeters}${l10n.translate('m_away') ?? 'm away'}', 
                  style: GoogleFonts.inter(
                    fontSize: 12, 
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
      ),
    );
  }

  Widget _buildQuickActions(AppLocalizations l10n) {
    return Row(
      children: [
        _quickActionBtn(Icons.account_balance_wallet_rounded, l10n.translate('top_up'), Colors.orange, () {
          final shell = context.findAncestorStateOfType<MainShellState>();
          if (shell != null) shell.setTab(3);
        }),
        const SizedBox(width: 12),
        _quickActionBtn(Icons.auto_awesome_rounded, l10n.translate('ai_support'), Colors.purple, () {
          Navigator.push(context, MaterialPageRoute(builder: (c) => const AiChatScreen()));
        }),
        const SizedBox(width: 12),
        _quickActionBtn(Icons.map_rounded, l10n.translate('map_view'), Colors.teal, () {
          final shell = context.findAncestorStateOfType<MainShellState>();
          if (shell != null) shell.setTab(1);
        }),
      ],
    );
  }

  Widget _quickActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
