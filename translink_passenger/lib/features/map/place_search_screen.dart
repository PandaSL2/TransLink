import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/theme/app_theme.dart';
import '../../models/bus_models.dart';
import '../../core/services/places_service.dart';
import '../../core/utils/app_localizations.dart';

class PlaceSearchScreen extends StatefulWidget {
  final String? initialQuery;
  const PlaceSearchScreen({super.key, this.initialQuery});

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _placesService = PlacesService();
  List<PlacePrediction> _suggestions = [];
  List<Map<String, dynamic>> _recentSearches = [];
  List<Map<String, dynamic>> _savedPlacesList = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _loadSavedPlaces();
    
    if (widget.initialQuery != null) {
      _searchCtrl.text = widget.initialQuery!;
      _onSearchChanged(widget.initialQuery!);
    }
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('recent_searches') ?? '[]';
    if (mounted) {
      setState(() {
        _recentSearches = List<Map<String, dynamic>>.from(json.decode(data));
      });
    }
  }

  Future<void> _loadSavedPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getString('saved_places_list');
    if (rawList != null) {
      setState(() => _savedPlacesList = List<Map<String, dynamic>>.from(json.decode(rawList)));
    }
  }

  Future<void> _toggleSaved(Map<String, dynamic> place) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final exists = _savedPlacesList.any((p) => p['label'] == place['mainText']);
      if (exists) {
        _savedPlacesList.removeWhere((p) => p['label'] == place['mainText']);
      } else {
        _savedPlacesList.add({
          'label': place['mainText'],
          'lat': place['lat'],
          'lng': place['lng'],
        });
      }
    });
    await prefs.setString('saved_places_list', json.encode(_savedPlacesList));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String val) async {
    if (val.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searching = true);
    final results = await _placesService.getSuggestions(val);
    if (mounted) {
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    }
  }

  Future<void> _onSelectPlace(PlacePrediction place) async {
    final loc = await _placesService.getPlaceLocation(place.placeId);
    if (loc != null && mounted) {
      final trip = TripModel(
        destinationName: place.mainText,
        destLat: loc['lat'],
        destLng: loc['lng'],
      );
      
      final prefs = await SharedPreferences.getInstance();
      final List<dynamic> history = json.decode(prefs.getString('recent_searches') ?? '[]');
      history.removeWhere((r) => r['placeId'] == place.placeId);
      history.insert(0, {
        'mainText': place.mainText,
        'secondaryText': place.secondaryText,
        'placeId': place.placeId,
        'lat': loc['lat'],
        'lng': loc['lng'],
      });
      if (history.length > 10) history.removeLast();
      await prefs.setString('recent_searches', json.encode(history));

      Navigator.pop(context, trip);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildFloatingSearchBar(l10n),
            if (_searching) const LinearProgressIndicator(color: AppColors.secondary, minHeight: 2),
            Expanded(
              child: _suggestions.isEmpty && _searchCtrl.text.isEmpty
                  ? _buildRecentList(l10n)
                  : _buildSuggestionsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingSearchBar(AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.4 : 0.08), 
            blurRadius: 15, 
            offset: const Offset(0, 8)
          ),
        ],
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.primary),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: l10n.translate('search_hint'),
                border: InputBorder.none,
                hintStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onPressed: () {
                _searchCtrl.clear();
                _onSearchChanged('');
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildRecentList(AppLocalizations l10n) {
    if (_recentSearches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 64, color: Theme.of(context).dividerColor),
            const SizedBox(height: 16),
            Text(l10n.translate('recents'), style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(l10n.translate('recent_label').toUpperCase(), style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey[400], letterSpacing: 1)),
        ),
        ..._recentSearches.map((r) {
          final isSaved = _savedPlacesList.any((p) => p['label'] == r['mainText']);
          return ListTile(
            leading: Icon(Icons.history_rounded, color: Theme.of(context).textTheme.bodySmall?.color, size: 20),
            title: Text(r['mainText'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: Theme.of(context).textTheme.bodyLarge?.color)),
            subtitle: Text(r['secondaryText'] ?? '', style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color), maxLines: 1),
            trailing: IconButton(
              icon: Icon(isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded, 
                color: isSaved ? Colors.redAccent : Colors.grey[300], size: 20),
              onPressed: () => _toggleSaved(r),
            ),
            onTap: () => Navigator.pop(context, TripModel(
              destinationName: r['mainText'],
              destLat: r['lat'],
              destLng: r['lng'],
            )),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          );
        }),
      ],
    );
  }

  Widget _buildSuggestionsList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _suggestions.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
      itemBuilder: (context, i) {
        final p = _suggestions[i];
        final isSaved = _savedPlacesList.any((place) => place['label'] == p.mainText);

        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.secondary.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.location_on_rounded, color: AppColors.secondary, size: 20),
          ),
          title: Text(p.mainText, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: Theme.of(context).textTheme.bodyLarge?.color)),
          subtitle: Text(p.secondaryText, style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: Icon(isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded, 
              color: isSaved ? Colors.redAccent : Colors.grey[300], size: 20),
            onPressed: () async {
              final loc = await _placesService.getPlaceLocation(p.placeId);
              if (loc != null) {
                _toggleSaved({
                  'mainText': p.mainText,
                  'lat': loc['lat'],
                  'lng': loc['lng'],
                });
              }
            },
          ),
          onTap: () => _onSelectPlace(p),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        );
      },
    );
  }
}
