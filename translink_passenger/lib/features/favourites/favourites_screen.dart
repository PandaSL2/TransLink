import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:translink_passenger/core/theme/app_theme.dart';
import 'package:translink_passenger/models/bus_models.dart';
import 'package:translink_passenger/ui/main_shell.dart';
import 'package:translink_passenger/core/services/directions_service.dart';
import 'package:translink_passenger/services/location_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:translink_passenger/core/utils/app_localizations.dart';

class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Saved Routes & Places Data
  List<AiDiscoveredRoute> _localFavs = [];
  List<Map<String, dynamic>> _localPlaces = [];
  bool _loadingFavs = true;

  // Timetable Data
  List<NearestBusStop> _nearbyStops = [];
  bool _loadingStops = true;
  final _directionsService = DirectionsService();
  final _locationService = LocationService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _loadNearbyStops();
  }

  @override
  void dispose() { 
    _tabController.dispose(); 
    super.dispose(); 
  }

  Future<void> _loadData() async {
    setState(() => _loadingFavs = true);
    final prefs = await SharedPreferences.getInstance();
    
    // Load Routes
    final dataStr = prefs.getString('fav_routes_data') ?? '{}';
    final Map<String, dynamic> data = json.decode(dataStr);
    final routes = data.values.map((v) => AiDiscoveredRoute.fromJson(v as Map<String, dynamic>)).toList();
    
    // Load Places
    final placesStr = prefs.getString('saved_places_list') ?? '[]';
    final List<dynamic> places = json.decode(placesStr);
    
    if (mounted) {
      setState(() { 
        _localFavs = routes; 
        _localPlaces = List<Map<String, dynamic>>.from(places);
        _loadingFavs = false; 
      });
    }
  }

  Future<void> _loadNearbyStops() async {
    setState(() => _loadingStops = true);
    try {
      final pos = await _locationService.getCurrentLocation();
      if (pos != null) {
        final stops = await _directionsService.findNearbyBusStops(pos.lat, pos.lng);
        if (mounted) setState(() { _nearbyStops = stops; });
      }
    } finally {
      if (mounted) setState(() => _loadingStops = false);
    }
  }

  void _restoreRoute(AiDiscoveredRoute r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_route', json.encode(r.toJson()));
    await prefs.setBool('is_ride_active', true);
    
    // Switch to Map tab in MainShell
    if (mounted) {
      final shell = context.findAncestorStateOfType<MainShellState>();
      if (shell != null) {
        shell.setTab(1); // 1 is Explore/Map
      }
    }
  }

  void _openGoogleMapsTimetable(NearestBusStop stop) async {
    // This intent URL opens the place directly in Google Maps which brings up transit boards
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${stop.lat},${stop.lng}&query_place_id=${stop.placeId ?? ""}'
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('could_not_open_maps'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.translate('schedule_saved')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              dividerColor: Colors.transparent,
              tabs: [Tab(text: l10n.translate('timetable_tab')), Tab(text: l10n.translate('saved_routes_tab'))],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _timetableList(),
          _favouritesList(_localFavs, _localPlaces),
        ],
      ),
    );
  }

  Widget _timetableList() {
    if (_loadingStops) return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));

    return RefreshIndicator(
      onRefresh: _loadNearbyStops,
      color: AppColors.secondary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(
              AppLocalizations.of(context)!.translate('nearby_bus_stops'),
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          if (_nearbyStops.isEmpty)
            _emptyTimetable()
          else
            ..._nearbyStops.map((stop) => _stopCard(stop)),
        ],
      ),
    );
  }

  Widget _stopCard(NearestBusStop stop) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.departure_board_rounded, color: Colors.blue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).textTheme.bodyLarge?.color),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.directions_walk_rounded, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${stop.walkingMinutes} ${AppLocalizations.of(context)!.translate('min_walk')} (${stop.walkingMeters}m)',
                        style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _openGoogleMapsTimetable(stop),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.secondary.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              AppLocalizations.of(context)!.translate('view_board'),
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyTimetable() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.location_off_rounded, color: Colors.blue, size: 36),
          ),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(context)!.translate('no_stops_nearby'), style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(AppLocalizations.of(context)!.translate('no_stops_sub'), style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _favouritesList(List<AiDiscoveredRoute> favs, List<Map<String, dynamic>> places) {
    if (_loadingFavs) return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.secondary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (favs.isEmpty && places.isEmpty)
            _emptyFavourites()
          else ...[
            if (places.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4),
                child: Text(
                  AppLocalizations.of(context)!.translate('saved_places') ?? 'Saved Places',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              ...places.map((p) => _placeCard(p)),
              const SizedBox(height: 24),
            ],
            if (favs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4),
                child: Text(
                  AppLocalizations.of(context)!.translate('saved_routes_tab'),
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              ...favs.map((f) => _favCard(f)),
            ],
          ],
          _addNewCard(),
        ],
      ),
    );
  }

  Widget _placeCard(Map<String, dynamic> place) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String label = place['label'] ?? 'Unknown';
    final double? lat = place['lat'];
    final double? lng = place['lng'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), 
            blurRadius: 15, offset: const Offset(0, 8)
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (lat != null && lng != null) {
                final shell = context.findAncestorStateOfType<MainShellState>();
                if (shell != null) {
                  shell.setTab(1, argument: TripModel(
                    destinationName: label,
                    destLat: lat,
                    destLng: lng,
                  ));
                }
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.place_rounded, 
                      color: Theme.of(context).colorScheme.primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, 
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800, 
                            fontSize: 17, 
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          )),
                        const SizedBox(height: 2),
                        Text('Saved Destination', 
                          style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.tertiary, size: 22),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final raw = prefs.getString('saved_places_list') ?? '[]';
                      final List<dynamic> list = json.decode(raw);
                      list.removeWhere((item) => item['label'] == label);
                      await prefs.setString('saved_places_list', json.encode(list));
                      _loadData();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _favCard(AiDiscoveredRoute fav) {
    return GestureDetector(
      onTap: () => _restoreRoute(fav),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.directions_bus_rounded, color: AppColors.secondary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${AppLocalizations.of(context)!.translate('route_prefix')} ${fav.routeNumber}',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    fav.routeName,
                    style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${fav.durationMinutes} ${AppLocalizations.of(context)!.translate('min_total')}',
                          style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.favorite_rounded, color: AppColors.error, size: 22),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final ids = prefs.getStringList('fav_routes') ?? [];
                final dataStr = prefs.getString('fav_routes_data') ?? '{}';
                final data = Map<String, dynamic>.from(json.decode(dataStr));
                
                ids.remove(fav.id);
                data.remove(fav.id);
                
                await prefs.setStringList('fav_routes', ids);
                await prefs.setString('fav_routes_data', json.encode(data));
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _addNewCard() {
    return GestureDetector(
      onTap: () {
        // Switch to Map tab
        final shell = context.findAncestorStateOfType<MainShellState>();
        if (shell != null) {
          shell.setTab(1);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.secondary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.secondary.withOpacity(0.2), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: AppColors.secondary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Icon(Icons.search_rounded, color: AppColors.secondary, size: 20)),
            ),
            const SizedBox(width: 10),
            Text(AppLocalizations.of(context)!.translate('search_new_route'), style: GoogleFonts.inter(color: AppColors.secondary, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _emptyFavourites() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: AppColors.secondary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.favorite_border_rounded, color: AppColors.secondary, size: 36),
          ),
          Text(AppLocalizations.of(context)!.translate('no_saved_routes'), style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(AppLocalizations.of(context)!.translate('no_saved_routes_sub'), style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
