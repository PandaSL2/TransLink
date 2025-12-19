import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:geolocator/geolocator.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_localizations.dart';
import '../../core/utils/geo_position.dart';
import '../../models/bus_models.dart';
import '../../core/services/directions_service.dart';
import '../../services/supabase_service.dart';
import '../../services/location_service.dart';
import '../../core/services/notification_service.dart';
import 'package:provider/provider.dart';
import 'place_search_screen.dart';
import 'widgets/bus_animation_overlay.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/ride_provider.dart';
import '../../core/services/settings_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  MapScreenState createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  gmaps.GoogleMapController? _mapController;
  final _directionsService = DirectionsService();
  final _locationService = LocationService();
  final _flutterTts = FlutterTts();

  // --- View State ---
  bool _isLoading = false;

  // --- Map Data ---
  static const GeoPosition _colombo = GeoPosition(79.8612, 6.9271);
  GeoPosition? _userPosition;
  final Set<gmaps.Marker> _markers = {};
  final Set<gmaps.Polyline> _polylines = {};

  // --- Route Data ---
  List<AiDiscoveredRoute> _routes = [];
  List<LiveBusData> _liveBuses = [];
  String _destLabel = "";
  List<AiDiscoveredRoute> _suggestedRoutesBackup = [];

  GeoPosition? _alightStopPos;
  bool _alightAlertTriggered = false;
  bool _anyBusMatch = false;
  StreamSubscription? _busStream;
  List<StopModel> _allStops = [];
  late final BusAnimationController _busAnimationController;
  
  // --- Animation Cache ---
  final Map<String, List<gmaps.LatLng>> _busTrails = {};
  final Map<String, DateTime> _lastUpdateTimes = {};

  // --- UI Controllers ---
  final _sheetCtrl = DraggableScrollableController();

  // --- Saved Locations ---
  Map<String, dynamic> _homeLocation = {'label': 'Home', 'lat': 0.0, 'lng': 0.0};
  Map<String, dynamic> _workLocation = {'label': 'Work', 'lat': 0.0, 'lng': 0.0};
  List<Map<String, dynamic>> _savedPlacesList = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectLocation();
    _initAnimationController();
    _startLiveTracking();
    _loadAllStops();
    _loadSavedLocations();
    _requestPermissions();
    
    // Proximity Alert Listener
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
    ).listen((pos) {
      if (mounted) {
        setState(() => _userPosition = GeoPosition(pos.longitude, pos.latitude));
        _checkAlightAlert();
      }
    });
    
    // Support swipe-down/drag to go back
    _sheetCtrl.addListener(() {
      final rideProvider = Provider.of<RideProvider>(context, listen: false);
      if (_sheetCtrl.isAttached && _sheetCtrl.size <= 0.12 && rideProvider.activeRoute != null) {
        if (mounted) {
          if (rideProvider.isRideActive) {
             // If ride is active, don't clear the search/route, just keep it minimized
             return;
          }
          setState(() {
            rideProvider.stopRide();
            _routes = List.from(_suggestedRoutesBackup);
            _suggestedRoutesBackup = [];
            _polylines.removeWhere((p) => p.polylineId.value.startsWith('route_'));
          });
        }
      }
    });
  }

  Future<void> _requestPermissions() async {
    await NotificationService.requestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _busStream?.cancel();
    _busAnimationController.dispose();
    _flutterTts.stop();
    _sheetCtrl.dispose();
    super.dispose();
  }

  void _shareJourney(AiDiscoveredRoute r) async {
    final pos = await Geolocator.getCurrentPosition();
    final String mapsLink = 'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';
    final String message = '🚍 Tracking my journey on Bus ${r.routeNumber} to ${r.routeName.split('→').last.trim()}.\n\n'
                           'Live Location: $mapsLink\n\n'
                           'Sent via Translink Passenger App';
    
    Share.share(message, subject: 'My Translink Journey');
  }

  // --- External Methods called by MainShell ---
  void handleNewTripFromHome(TripModel trip) {
    if (trip.destinationName != null && trip.destLat != null) {
      _searchDestination(trip.destinationName!, gmaps.LatLng(trip.destLat!, trip.destLng!));
    }
  }

  // --- Logic Methods ---
  Future<void> _detectLocation() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (!settings.locationAutoDetect && _userPosition != null) return;

    final pos = await _locationService.getCurrentLocation();
    if (pos != null && mounted) {
      setState(() {
        _userPosition = pos;
      });
      
      final currentZoom = await _mapController?.getZoomLevel() ?? 0;
      final targetZoom = currentZoom < 15 ? 16.0 : currentZoom;
      
      _mapController?.animateCamera(gmaps.CameraUpdate.newCameraPosition(
        gmaps.CameraPosition(target: gmaps.LatLng(pos.lat, pos.lng), zoom: targetZoom)
      ));
    }
  }

  void _initAnimationController() {
    _busAnimationController = BusAnimationController(
      vsync: this,
      onUpdate: (icons) {
        if (mounted) {
          _syncBusMarkers(_liveBuses);
        }
      },
    );
  }

  void _startLiveTracking() {
    _busStream?.cancel();
    _busStream = SupabaseService.getLiveBusesStream().listen((buses) async {
      if (mounted) {
        debugPrint('🚏 MapScreen: Received \${buses.length} live buses from Supabase.');
        setState(() => _liveBuses = buses);
        await _busAnimationController.updateBuses(buses);
        _checkAlightAlert();
      }
    }, onError: (e) => debugPrint('🚨 Bus Stream Error: $e'));
  }

  void _syncBusMarkers(List<LiveBusData> buses) {
    if (!mounted) return;
    
    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final selectedRoute = rideProvider.activeRoute;

    // 1. Quick Exit if Disabled
    if (!settings.showVirtualBuses) {
      if (_markers.any((m) => m.markerId.value.startsWith('bus_'))) {
        setState(() {
          _markers.removeWhere((m) => m.markerId.value.startsWith('bus_'));
          _polylines.removeWhere((p) => p.polylineId.value.startsWith('trail_'));
        });
      }
      return;
    }

    // 2. Pre-filter buses to prevent heavy logic in animation frames
    bool matchedAtLeastOne = false;
    final Set<gmaps.Marker> newMarkers = Set.from(_markers.where((m) => !m.markerId.value.startsWith('bus_')));
    final Set<gmaps.Polyline> newPolylines = Set.from(_polylines.where((p) => !p.polylineId.value.startsWith('trail_')));
    
    // --- DYNAMIC FILTERING LOGIC ---
    final bool isSearchActive = _routes.isNotEmpty;
    final bool isSelectionActive = selectedRoute != null;
    final bool shouldFilter = isSearchActive || isSelectionActive;

    // Collect all "relevant" route numbers to display
    final Set<String> relevantRouteNumbers = {};
    if (isSelectionActive) {
      for (var segment in selectedRoute.segments) {
        if (segment.routeNumber != null) {
          relevantRouteNumbers.add(segment.routeNumber!.toUpperCase().trim());
        }
      }
    } else if (isSearchActive) {
      for (var route in _routes) {
        for (var segment in route.segments) {
          if (segment.routeNumber != null) {
            relevantRouteNumbers.add(segment.routeNumber!.toUpperCase().trim());
          }
        }
      }
    }

    // Find nearest stop for ETA once (outside the bus loop)
    StopModel? nearestUserStop;
    if (_userPosition != null && _allStops.isNotEmpty) {
      double minDist = 5000; // Only care about stops within 5km for ETA
      for (var stop in _allStops) {
        final d = _locationService.calculateDistance(_userPosition!.lat, _userPosition!.lng, stop.lat, stop.lng);
        if (d < minDist) {
          minDist = d;
          nearestUserStop = stop;
        }
      }
    }

    for (final bus in buses) {
      // 1. Initial State: Show all unless filtering is active
      bool isMatch = !shouldFilter; 
      
      if (shouldFilter) {
        final busNumUpper = bus.routeNumber.toUpperCase().trim();
        final busDigits = busNumUpper.replaceAll(RegExp(r'[^0-9]'), '');

        // Primary Match: Check against relevantRouteNumbers set
        for (var relNumber in relevantRouteNumbers) {
          final relDigits = relNumber.replaceAll(RegExp(r'[^0-9]'), '');
          
          // EXPERT MATCH: Exact, Substring, or Numerical Match (e.g., "689A" matches "689")
          if (relNumber == busNumUpper || 
              relNumber.contains(busNumUpper) || 
              busNumUpper.contains(relNumber) || 
             (relDigits == busDigits && relDigits.isNotEmpty)) {
            isMatch = true;
            break;
          }
        }

        // 2. FAIL-SAFE / SEMANTIC MATCH (Only for Selection mode or if no match found)
        if (!isMatch && isSelectionActive && relevantRouteNumbers.isEmpty && bus.routeName.isNotEmpty && selectedRoute.routeName.isNotEmpty) {
          final busParts = bus.routeName.toLowerCase().split(RegExp(r'[\s\-\>]+'));
          final routeParts = selectedRoute.routeName.toLowerCase().split(RegExp(r'[\s\-\>]+'));
          for (var part in busParts) {
            if (part.length > 3 && routeParts.contains(part)) {
              isMatch = true;
              break;
            }
          }
        }
        
        if (!isMatch) continue;
        matchedAtLeastOne = true;
      }

      final id = bus.busNumber;
      final animPos = _busAnimationController.getPosition(id);
      final animRot = _busAnimationController.getRotation(id);
      final icon = _busAnimationController.getIcon(id, bus.fleetType, bus.status) ?? _busAnimationController.defaultIcon;
      final finalPos = animPos.latitude != 0 ? animPos : gmaps.LatLng(bus.lat, bus.lng);

      if (finalPos.latitude != 0) {
        // Trail Logic (Throttled update)
        if (!_busTrails.containsKey(id)) _busTrails[id] = [];
        if (_busTrails[id]!.isEmpty || (_busTrails[id]!.last.latitude != finalPos.latitude)) {
          _busTrails[id]!.add(finalPos);
          if (_busTrails[id]!.length > 10) _busTrails[id]!.removeAt(0);
        }

        if (_busTrails[id]!.length > 1) {
          newPolylines.add(gmaps.Polyline(
            polylineId: gmaps.PolylineId('trail_$id'),
            points: _busTrails[id]!,
            color: AppColors.secondary.withOpacity(0.35),
            width: 3,
            zIndex: 1,
          ));
        }

        newMarkers.add(gmaps.Marker(
          markerId: gmaps.MarkerId('bus_$id'),
          position: finalPos, 
          rotation: animRot,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          zIndex: 5,
          infoWindow: gmaps.InfoWindow(
            title: '${bus.routeNumber} - ${bus.busNumber}',
          ),
        ));
      }
    }
    
    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(newMarkers);
        _polylines.clear();
        _polylines.addAll(newPolylines);
        _anyBusMatch = matchedAtLeastOne;
      });
    }
  }


    Future<void> _loadAllStops() async {
      try {
        final stops = await SupabaseService.getAllStops();
        if (mounted) setState(() => _allStops = stops);
      } catch (_) {}
    }

  void _checkAlightAlert() {
    if (_userPosition == null || _alightStopPos == null || _alightAlertTriggered) {
      return;
    }
    
    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    if (!rideProvider.isRemindMeActive) return;

    final dist = _locationService.calculateDistance(
      _userPosition!.lat, _userPosition!.lng,
      _alightStopPos!.lat, _alightStopPos!.lng);
    
    if (dist < 500) {
      _alightAlertTriggered = true;
      rideProvider.setRemindMe(false); // One-time trigger
      
      // Native Vibration Pattern (Triple pulse)
      HapticFeedback.vibrate();
      Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.vibrate());
      Future.delayed(const Duration(milliseconds: 600), () => HapticFeedback.vibrate());

      NotificationService.showNotification(
        id: (DateTime.now().millisecondsSinceEpoch / 1000).remainder(1000).toInt(),
        title: AppLocalizations.of(context)!.translate('approaching_stop'),
        body: AppLocalizations.of(context)!.translate('approaching_stop_msg'),
      );
    }
    // Shared persistence logic
    if (dist < 100 && !rideProvider.isSharingActive && !rideProvider.isRideActive) {
      _clearSearch();
    }
  }

  Future<void> _searchDestination(String label, gmaps.LatLng latLng) async {
    // Strictly enforce one ride only: Clear any existing state before a new search
    _clearSearch();
    
    setState(() {
      _isLoading = true;
      _destLabel = label;
      _markers.add(gmaps.Marker(
        markerId: const gmaps.MarkerId('dest'),
        position: latLng,
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueRed),
      ));
    });
    
    final transitResults = await _directionsService.getTransitRoute(
      _userPosition?.lat ?? _colombo.lat, 
      _userPosition?.lng ?? _colombo.lng,
      latLng.latitude, 
      latLng.longitude
    );
    
    final List<AiDiscoveredRoute> enrichedRoutes = [];
    for (final t in transitResults) {
      final route = await _directionsService.buildBusRoute(transit: t, destLabel: label);
      enrichedRoutes.add(route);
    }
    
    if (mounted) {
      setState(() {
        _routes = enrichedRoutes;
        _isLoading = false;
      });
      _sheetCtrl.animateTo(0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _selectRoute(AiDiscoveredRoute r) {
    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    rideProvider.updateActiveRoute(r);
    
    setState(() {
      _suggestedRoutesBackup = List.from(_routes);
      _routes = [];
      _alightStopPos = r.destPosition;
      
      _syncBusMarkers(_liveBuses);
      
      int segmentIndex = 0;
      for (final segment in r.segments) {
        _polylines.add(gmaps.Polyline(
          polylineId: gmaps.PolylineId('route_$segmentIndex'),
          points: segment.polyline.map((p) => gmaps.LatLng(p.lat, p.lng)).toList(),
          color: segment.color,
          width: 5,
          patterns: segment.type == SegmentType.walking 
              ? [gmaps.PatternItem.dot, gmaps.PatternItem.gap(10)] 
              : const [],
        ));
        segmentIndex++;
      }
    });
    _sheetCtrl.animateTo(0.45, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  bool tryClearSearch() {
    if (_destLabel.isNotEmpty) {
      _clearSearch();
      return true;
    }
    return false;
  }

  void _clearSearch() {
    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    rideProvider.updateActiveRoute(null);
    rideProvider.stopRide();
    
    setState(() {
      _destLabel = "";
      _routes = [];
      _markers.clear();
      _polylines.clear();
      _anyBusMatch = false;
    });
    
    _syncBusMarkers(_liveBuses);
    _sheetCtrl.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // --- Saved Locations Logic ---
  Future<void> _loadSavedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final rawHome = prefs.getString('saved_home');
    if (rawHome != null) {
      _homeLocation = json.decode(rawHome);
    }
    final rawWork = prefs.getString('saved_work');
    if (rawWork != null) {
      _workLocation = json.decode(rawWork);
    }
    final rawList = prefs.getString('saved_places_list');
    if (rawList != null) {
      _savedPlacesList = List<Map<String, dynamic>>.from(json.decode(rawList));
    }
    setState(() {});
  }

  Future<void> _saveSavedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_home', json.encode(_homeLocation));
    await prefs.setString('saved_work', json.encode(_workLocation));
    await prefs.setString('saved_places_list', json.encode(_savedPlacesList));
  }

  bool get _isSearchActive => _routes.isNotEmpty || _destLabel.isNotEmpty || Provider.of<RideProvider>(context, listen: false).activeRoute != null;

  // --- UI Build Methods ---
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    final rideProvider = Provider.of<RideProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final selectedRoute = rideProvider.activeRoute;
    final isSearchActive = _isSearchActive;
    
    return PopScope(
      canPop: true, // Allow back navigation, the ride stays active in the provider
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        
        // If sheet is expanded but ride NOT active, minimize sheet on back press
        if (selectedRoute != null && !rideProvider.isRideActive) {
          _sheetCtrl.animateTo(0.1, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          setState(() {
            rideProvider.stopRide();
            _routes = List.from(_suggestedRoutesBackup);
            _suggestedRoutesBackup = [];
            _polylines.removeWhere((p) => p.polylineId.value.startsWith('route_'));
          });
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            gmaps.GoogleMap(
              onMapCreated: (c) => _mapController = c,
              initialCameraPosition: gmaps.CameraPosition(target: gmaps.LatLng(_colombo.lat, _colombo.lng), zoom: 12),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapType: _getMapType(settings.mapStyle),
            ),
            _buildMyLocationButton(),
            _buildQuickPayFAB(),
            _buildHeader(l10n),
            _buildDraggableSheet(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPayFAB() {
    final rideProvider = Provider.of<RideProvider>(context);
    final route = rideProvider.activeRoute;
    if (route == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 200,
      right: 16,
      child: Column(
        children: [
          FloatingActionButton(
            onPressed: () => _showPaymentQR(route),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Container(
             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
             decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
             child: Text('PAY', style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildMyLocationButton() {
    return Positioned(
      bottom: 140,
      right: 16,
      child: FloatingActionButton(
        onPressed: _detectLocation,
        backgroundColor: Theme.of(context).cardColor,
        mini: true,
        child: Icon(Icons.my_location_rounded, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16, right: 16,
      child: Column(
        children: [
          _buildSearchBox(l10n),
          const SizedBox(height: 12),
          _buildQuickActions(l10n),
        ],
      ),
    );
  }

  Widget _buildSearchBox(AppLocalizations l10n) {
    return GestureDetector(
      onTap: () async {
        final res = await Navigator.push(context, MaterialPageRoute(builder: (c) => const PlaceSearchScreen()));
        if (res is TripModel) {
          _searchDestination(res.destinationName ?? 'Destination', gmaps.LatLng(res.destLat ?? 0, res.destLng ?? 0));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, 
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.black.withOpacity(0.5) : Colors.black.withOpacity(0.08), 
              blurRadius: 15, 
              offset: const Offset(0, 8)
            )
          ],
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _destLabel.isEmpty ? l10n.translate('search_hint') : _destLabel,
                style: GoogleFonts.inter(
                  color: _destLabel.isEmpty ? Theme.of(context).textTheme.bodySmall?.color : Theme.of(context).textTheme.bodyLarge?.color,
                  fontSize: 16
                ),
              ),
            ),
            if (_destLabel.isNotEmpty)
              IconButton(icon: Icon(Icons.close_rounded, color: Theme.of(context).textTheme.bodySmall?.color), onPressed: _clearSearch),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(AppLocalizations l10n) {
    if (_destLabel.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildQuickActionItem(l10n.translate('home'), Icons.home_rounded, _homeLocation, 'Home'),
          const SizedBox(width: 8),
          _buildQuickActionItem(l10n.translate('work'), Icons.work_rounded, _workLocation, 'Work'),
          const SizedBox(width: 8),
          _buildSavedAction(l10n),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem(String label, IconData icon, Map<String, dynamic> loc, String key) {
    bool isSet = loc['lat'] != 0.0;
    return GestureDetector(
      onTap: () {
        if (isSet) {
          _searchDestination(loc['label'], gmaps.LatLng(loc['lat'], loc['lng']));
        } else {
          _showSetLocationDialog(key);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, 
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSet ? Theme.of(context).colorScheme.primary : Theme.of(context).disabledColor),
            const SizedBox(width: 8),
            Text(isSet ? label : 'Set $label', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).textTheme.bodyLarge?.color)),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedAction(AppLocalizations l10n) {
    return GestureDetector(
      onTap: _showSavedPlacesSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, 
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Text(l10n.translate('saved_nav'), style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).textTheme.bodyLarge?.color)),
          ],
        ),
      ),
    );
  }

  void _showPaymentQR(AiDiscoveredRoute r) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final user = SupabaseService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login to pay via QR')));
      return;
    }

    final destinationName = r.routeName.split(RegExp(r'[→➔]')).last.trim().replaceFirst(RegExp(r'^(Transit to |To )', caseSensitive: false), '');

    // JSON format: {"uid": "...", "fare": ..., "dest": "..."}
    final qrData = json.encode({
      'uid': user.id,
      'fare': r.estimatedFareLkr,
      'route': r.routeNumber,
      'dest': destinationName,
      'ts': DateTime.now().toIso8601String(),
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 44, height: 5, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 28),
            Text(l10n.translate('scan_to_pay'), style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            Text(l10n.translate('show_to_conductor'), style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 36),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 10))],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 220.0,
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 36),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payments_rounded, color: Theme.of(context).colorScheme.secondary, size: 28),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      'Rs. ${r.estimatedFareLkr.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(l10n.translate('close'), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSavedPlacesSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.trOf(context, 'saved_nav'), style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (_savedPlacesList.isEmpty) 
               Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Text(AppLocalizations.trOf(context, 'no_saved_routes_msg')))
            else
              ..._savedPlacesList.map((p) => ListTile(
                leading: const Icon(Icons.place_rounded, color: AppColors.secondary),
                title: Text(p['label']),
                onTap: () {
                  Navigator.pop(ctx);
                  _searchDestination(p['label'], gmaps.LatLng(p['lat'], p['lng']));
                },
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {
                  setState(() => _savedPlacesList.remove(p));
                  _saveSavedLocations();
                  Navigator.pop(ctx);
                }),
              )),
          ],
        ),
      ),
    );
  }

  void _showSetLocationDialog(String key) async {
    final res = await Navigator.push(context, MaterialPageRoute(builder: (c) => const PlaceSearchScreen()));
    if (res is TripModel) {
      final loc = {'label': res.destinationName, 'lat': res.destLat, 'lng': res.destLng};
      setState(() {
        if (key == 'Home') {
          _homeLocation = loc;
        } else if (key == 'Work') {
          _workLocation = loc;
        } else {
          _savedPlacesList.add(loc);
        }
      });
      _saveSavedLocations();
    }
  }

  Widget _buildDraggableSheet(AppLocalizations l10n) {
    final rideProvider = Provider.of<RideProvider>(context);
    final selectedRoute = rideProvider.activeRoute;

    return DraggableScrollableSheet(
      controller: _sheetCtrl,
      initialChildSize: 0.12,
      minChildSize: 0.08,
      maxChildSize: 0.9,
      builder: (context, sc) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, 
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.6 : 0.1), 
              blurRadius: 25, 
              offset: const Offset(0, -5)
            )
          ],
          border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
        ),
        child: ListView(
          controller: sc,
          physics: const BouncingScrollPhysics(),
          children: [
            Center(child: Container(width: 44, height: 5, margin: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(10)))),
            if (_isLoading) 
              Center(child: Padding(padding: const EdgeInsets.all(48), child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 3)))
            else if (selectedRoute != null) 
              ..._buildRouteDetails(l10n, selectedRoute)
            else if (_routes.isNotEmpty) 
              ..._buildDiscovery(l10n)
            else 
              _buildEmptySheet(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySheet(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.directions_bus_rounded, color: Colors.grey[200], size: 64),
          const SizedBox(height: 16),
          Text(l10n.translate('search_to_see_routes'), textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14)),
        ],
      ),
    );
  }

  List<Widget> _buildDiscovery(AppLocalizations l10n) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 24, 16),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary, size: 28),
              onPressed: _clearSearch,
            ),
            const SizedBox(width: 4),
            Text(l10n.translate('suggested_routes'), style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ],
        ),
      ),
      ..._routes.map((r) => GestureDetector(
        onTap: () => _selectRoute(r),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.04),
                blurRadius: 15,
                offset: const Offset(0, 6),
              )
            ],
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14), 
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(16)
                ), 
                child: Icon(
                  r.segments.any((s) => s.type == SegmentType.bus) 
                    ? Icons.directions_bus_rounded 
                    : Icons.directions_walk_rounded, 
                  color: Theme.of(context).colorScheme.secondary
                )
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.routeNumber.isNotEmpty)
                      Text('Route ${r.routeNumber}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 17, color: Theme.of(context).colorScheme.onSurface))
                    else
                      Text('Walk', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 20, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 6),
                    Text(r.routeName, style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w500), softWrap: true),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text('${r.durationMinutes} mins', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(width: 20),
                        if (r.estimatedFareLkr > 0) ...[
                          Icon(Icons.payments_rounded, size: 16, color: Theme.of(context).colorScheme.secondary),
                          const SizedBox(width: 6),
                          Text('Rs. ${r.estimatedFareLkr.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Theme.of(context).dividerColor),
            ],
          ),
        ),
      )),
      const SizedBox(height: 20),
    ];
  }

  List<Widget> _buildRouteDetails(AppLocalizations l10n, AiDiscoveredRoute r) {
    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    bool isRouteActive = _liveBuses.any((b) => b.routeNumber == r.routeNumber);
    final anyBusMatch = _anyBusMatch;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary, size: 28),
              onPressed: () {
                if (rideProvider.isRideActive) {
                  _sheetCtrl.animateTo(0.1, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                  return;
                }
                setState(() {
                  rideProvider.stopRide();
                  _routes = List.from(_suggestedRoutesBackup);
                  _suggestedRoutesBackup = [];
                  _polylines.removeWhere((p) => p.polylineId.value.startsWith('route_'));
                });
              },
            ),
            const SizedBox(width: 8),
            Text(
              isRouteActive ? 'Route Details' : 'Waiting for bus...', 
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary)
            ),
            const Spacer(),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (anyBusMatch)
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(seconds: 1),
                  builder: (context, value, child) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary.withOpacity(0.1 + (0.1 * value)),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Theme.of(context).colorScheme.secondary.withOpacity(0.3 * value)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n.translate('live_tracking_badge').toUpperCase(),
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary, letterSpacing: 1.2),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      r.routeNumber ?? '—',
                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSecondary),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'To ${r.routeName.split(RegExp(r'[→➔]')).last.trim().replaceFirst(RegExp(r'^(Transit to |To )', caseSensitive: false), '')}',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text(isRouteActive ? 'ACTIVE' : 'WAITING', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                r.routeName, 
                style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w500, height: 1.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 28),
              // --- Redesigned Action Cluster ---
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () {
                        if (rideProvider.isRideActive) {
                          rideProvider.stopRide();
                          _clearSearch();
                        } else {
                          rideProvider.startRide(r);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rideProvider.isRideActive ? AppColors.error : Theme.of(context).colorScheme.secondary,
                        foregroundColor: rideProvider.isRideActive ? Colors.white : Theme.of(context).colorScheme.onSecondary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: Text(
                        rideProvider.isRideActive ? 'STOP RIDE' : 'START ROUTE',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                rideProvider.toggleRemindMe();
                                if (rideProvider.isRemindMeActive) {
                                  _alightAlertTriggered = false;
                                }
                              });
                            },
                            icon: Icon(rideProvider.isRemindMeActive ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, size: 20),
                            label: Text(rideProvider.isRemindMeActive ? 'REMINDING...' : 'REMIND ME'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: rideProvider.isRemindMeActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                              foregroundColor: rideProvider.isRemindMeActive ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).dividerColor)),
                              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      if (rideProvider.isRideActive) ...[
                        const SizedBox(width: 14),
                        IconButton(
                          onPressed: () => _shareJourney(r),
                          icon: Icon(Icons.share_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                            padding: const EdgeInsets.all(16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).dividerColor)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          anyBusMatch ? 'Bus is active. Tracking...' : 'Searching for live buses...',
                          style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 14)
                        ),
                        const SizedBox(height: 4),
                        if (!anyBusMatch)
                          Text(
                            'Checking route for live updates',
                            style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4),
                            softWrap: true,
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.sync_rounded, color: isRouteActive ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5), size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.translate('journey_details'), style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
            Text('${r.durationMinutes} ${l10n.translate('min_total')}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.secondary, fontSize: 16)),
          ],
        ),
      ),
      ..._buildTimeline(r),
      const SizedBox(height: 24),
      IntrinsicHeight(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _metricCard(Icons.access_time_filled_rounded, l10n.translate('duration_label'), '${r.durationMinutes} ${l10n.translate('min')}', Theme.of(context).colorScheme.primary)),
              const SizedBox(width: 8),
              Expanded(child: _metricCard(Icons.straighten_rounded, l10n.translate('distance_label'), '${r.distanceKm.toStringAsFixed(1)} km', Theme.of(context).colorScheme.primary)),
              const SizedBox(width: 8),
              Expanded(child: _metricCard(Icons.directions_walk_rounded, l10n.translate('walk_label'), '${r.walkingMeters} m', Theme.of(context).colorScheme.primary)),
              if (r.estimatedFareLkr > 0) ...[
                const SizedBox(width: 8),
                Expanded(child: _metricCard(Icons.payments_rounded, l10n.translate('est_fare_label'), 'Rs. ${r.estimatedFareLkr.toStringAsFixed(0)}', Theme.of(context).colorScheme.primary)),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      // Bottom action removed as it is now inside the card
      const SizedBox(height: 12),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _buildTimeline(AiDiscoveredRoute r) {
    List<Widget> steps = [];
    for (int i = 0; i < r.segments.length; i++) {
      final seg = r.segments[i];
      final isLast = i == r.segments.length - 1;
      final isWalk = seg.type == SegmentType.walking;
      
      steps.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: isWalk 
                        ? (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey[100])
                        : AppColors.secondary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isWalk ? Icons.directions_walk_rounded : Icons.directions_bus_rounded,
                      size: 16,
                      color: isWalk ? Theme.of(context).textTheme.bodySmall?.color : AppColors.secondary,
                    )
                  ),
                  if (!isLast)
                    Container(width: 2, height: 30, color: Theme.of(context).dividerColor),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 4.0 : 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          isWalk ? seg.instruction : 'Bus ${seg.routeNumber ?? ""}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, 
                            fontSize: 14, 
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                            height: 1.3
                          ),
                          softWrap: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${seg.durationMin} min', 
                        style: GoogleFonts.inter(
                          color: Theme.of(context).textTheme.bodySmall?.color, 
                          fontSize: 12,
                          fontWeight: FontWeight.w500
                        )
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        )
      );
    }
    return steps;
  }

  Widget _metricCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 18),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 30, // Fixed height for labels to handle wrap balancing
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800, letterSpacing: 0.1),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 16, color: Theme.of(context).colorScheme.primary))
          ),
        ],
      ),
    );
  }

  gmaps.MapType _getMapType(String style) {
    switch (style) {
      case 'Satellite (OSM)': return gmaps.MapType.satellite;
      case 'Minimal': return gmaps.MapType.terrain;
      case 'Standard':
      default: return gmaps.MapType.normal;
    }
  }
}
