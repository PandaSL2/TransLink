import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_localizations.dart';
import '../../core/services/directions_service.dart';
import '../../services/location_service.dart';
import '../map/place_search_screen.dart';
import '../../core/services/settings_provider.dart';
import '../../ui/main_shell.dart';
import '../../models/bus_models.dart';
import '../ai/ai_chat_screen.dart';
import '../../core/widgets/tl_bus_stop_card.dart';
import '../../core/widgets/tl_live_board_sheet.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _directionsService = DirectionsService();
  final _locationService = LocationService();
  final SpeechToText _speech = SpeechToText();

  List<NearestBusStop> _nearbyStops = [];
  bool _isLoadingStops = true;
  bool _isListening = false;

  // GPS reverse-geocoded address shown in the From row
  String _currentLocationLabel = 'Detecting location...';
  TripModel? _customOrigin;

  @override
  void initState() {
    super.initState();
    _loadNearbyStops();
    _resolveCurrentAddress();
  }

  void resetCustomOrigin() {
    if (_customOrigin != null && mounted) {
      setState(() {
        _customOrigin = null;
        _currentLocationLabel = 'Detecting location...';
      });
      _resolveCurrentAddress();
    }
  }

  /// Reverse-geocode the user's GPS position into a human-readable address.
  Future<void> _resolveCurrentAddress() async {
    try {
      final pos = await _locationService.getCurrentLocation();
      if (pos == null) {
        if (mounted) setState(() => _currentLocationLabel = 'My Location');
        return;
      }
      final placemarks = await placemarkFromCoordinates(pos.lat, pos.lng);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        // Focus on exact locality (e.g. Thalagala instead of Homagama)
        final parts = [p.street, p.subLocality, p.locality]
            .where((s) => s != null && s.isNotEmpty)
            .toList();
            
        // Filter out Google Maps plus codes like 'WV2C+43'
        final cleanParts = parts.where((p) => !p!.contains('+')).toSet().toList();
        
        setState(() {
          _currentLocationLabel = cleanParts.isNotEmpty ? cleanParts.first! : 'My Location';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _currentLocationLabel = 'My Location');
    }
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
       if (shell != null) {
          final enrichedTrip = TripModel(
             originName: _customOrigin?.destinationName,
             originLat: _customOrigin?.destLat,
             originLng: _customOrigin?.destLng,
             destinationName: res.destinationName,
             destLat: res.destLat,
             destLng: res.destLng,
          );
          shell.setTab(1, argument: enrichedTrip);
       }
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
                  const SizedBox(height: 28),
                  _buildSectionHeader(l10n.translate('nearby_stops'), () {
                    final shell = context.findAncestorStateOfType<MainShellState>();
                    if (shell != null) shell.setTab(2);
                  }, l10n),
                  const SizedBox(height: 16),
                  _buildNearbyStopsList(l10n),
                  const SizedBox(height: 28),
                  _buildSectionHeader(l10n.translate('quick_actions'), null, l10n),
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
    final settings = Provider.of<SettingsProvider>(context);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          // ── From row (GPS address, tappable to override) ────────
          GestureDetector(
            onTap: () async {
              final res = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlaceSearchScreen()),
              );
              // If user picked a custom from-location, update label
              if (res is TripModel && res.destinationName != null && mounted) {
                setState(() {
                  _customOrigin = res;
                  _currentLocationLabel = res.destinationName!;
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.liveGreen,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.liveGreen.withOpacity(0.35), width: 3),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _currentLocationLabel,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.liveGreen,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.edit_location_alt_rounded,
                      size: 16, color: AppColors.liveGreen),
                ],
              ),
            ),
          ),

          // ── Connector line ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Container(width: 1, height: 10,
                color: Theme.of(context).dividerColor),
          ),

          // ── To row (search destination + voice mic here) ────────
          GestureDetector(
            onTap: () => _navigateToSearch(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l10n.translate('search_hint'),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.55),
                      ),
                    ),
                  ),
                  // Voice button now lives in destination row
                  GestureDetector(
                    onTap: _startListening,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isListening
                            ? AppColors.error.withOpacity(0.1)
                            : Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_none_rounded,
                        color: _isListening
                            ? AppColors.error
                            : Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Quick-place chips ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _placeChip(
                    icon: Icons.home_rounded,
                    label: l10n.translate('home'),
                    onTap: () => _tapHomeChip(settings, l10n),
                  ),
                  const SizedBox(width: 8),
                  _placeChip(
                    icon: Icons.work_rounded,
                    label: l10n.translate('work'),
                    onTap: () => _tapWorkChip(settings, l10n),
                  ),
                  const SizedBox(width: 8),
                  _placeChip(
                    icon: Icons.star_rounded,
                    label: l10n.translate('saved_nav'),
                    onTap: () {
                      final shell =
                          context.findAncestorStateOfType<MainShellState>();
                      if (shell != null) shell.setTab(2);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Home chip logic ───────────────────────────────────────────────
  void _tapHomeChip(SettingsProvider settings, AppLocalizations l10n) async {
    if (settings.homePlace != null) {
      // Navigate directly
      final shell = context.findAncestorStateOfType<MainShellState>();
      if (shell != null) {
        shell.setTab(1, argument: TripModel(
          originName: _customOrigin?.destinationName,
          originLat: _customOrigin?.destLat,
          originLng: _customOrigin?.destLng,
          destinationName: settings.homePlace!.name,
          destLat: settings.homePlace!.lat,
          destLng: settings.homePlace!.lng,
        ));
      }
    } else {
      // Prompt user to set home
      _showSetPlaceSheet(
        title: l10n.translate('search_set_home'),
        icon: Icons.home_rounded,
        onSave: (place) => settings.setHomePlace(place),
      );
    }
  }

  // ── Work chip logic ───────────────────────────────────────────────
  void _tapWorkChip(SettingsProvider settings, AppLocalizations l10n) async {
    if (settings.workPlace != null) {
      final shell = context.findAncestorStateOfType<MainShellState>();
      if (shell != null) {
        shell.setTab(1, argument: TripModel(
          originName: _customOrigin?.destinationName,
          originLat: _customOrigin?.destLat,
          originLng: _customOrigin?.destLng,
          destinationName: settings.workPlace!.name,
          destLat: settings.workPlace!.lat,
          destLng: settings.workPlace!.lng,
        ));
      }
    } else {
      _showSetPlaceSheet(
        title: l10n.translate('search_set_work'),
        icon: Icons.work_rounded,
        onSave: (place) => settings.setWorkPlace(place),
      );
    }
  }

  // ── Set place bottom sheet ────────────────────────────────────────
  void _showSetPlaceSheet({
    required String title,
    required IconData icon,
    required Function(SavedPlace) onSave,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SetPlaceSheet(
        title: title,
        icon: icon,
        onSave: onSave,
      ),
    );
  }

  Widget _placeChip({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
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

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _nearbyStops.length > 3 ? 3 : _nearbyStops.length,
      itemBuilder: (context, i) => _buildStopCard(_nearbyStops[i], l10n),
    );
  }

  Widget _buildStopCard(NearestBusStop stop, AppLocalizations l10n) {
    return TLBusStopCard(
      stopName: stop.name,
      walkingMeters: stop.walkingMeters,
      walkingMinutes: stop.walkingMinutes,
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
      onViewBoard: () => TLLiveBoardSheet.show(context, stop),
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
        _quickActionBtn(Icons.account_balance_wallet_rounded, l10n.translate('top_up'), AppColors.primary, () {
          final shell = context.findAncestorStateOfType<MainShellState>();
          if (shell != null) shell.setTab(3);
        }),
        const SizedBox(width: 12),
        _quickActionBtn(Icons.auto_awesome_rounded, l10n.translate('ai_support'), AppColors.primary, () {
          Navigator.push(context, MaterialPageRoute(builder: (c) => const AiChatScreen()));
        }),
        const SizedBox(width: 12),
        _quickActionBtn(Icons.map_rounded, l10n.translate('map_view'), AppColors.primary, () {
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
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.12)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
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

// ── Set Place Bottom Sheet ────────────────────────────────────────────────────
/// Shown when user taps Home or Work chip without a saved place.
/// Lets them search and save their location.
class _SetPlaceSheet extends StatefulWidget {
  final String title;
  final IconData icon;
  final Function(SavedPlace) onSave;

  const _SetPlaceSheet({
    required this.title,
    required this.icon,
    required this.onSave,
  });

  @override
  State<_SetPlaceSheet> createState() => _SetPlaceSheetState();
}

class _SetPlaceSheetState extends State<_SetPlaceSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24, right: 24, top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.title,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PlaceSearchScreen(),
                  ),
                );
                if (res is TripModel &&
                    res.destinationName != null &&
                    res.destLat != null &&
                    res.destLng != null) {
                  widget.onSave(SavedPlace(
                    name: res.destinationName!,
                    lat: res.destLat!,
                    lng: res.destLng!,
                  ));
                }
              },
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search a location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
