import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';

class PlacePrediction {
  final String mainText;
  final String secondaryText;
  final String fullText;
  final String placeId;

  PlacePrediction({
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
    required this.placeId,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structured = json['structured_formatting'];
    return PlacePrediction(
      mainText: structured?['main_text'] as String? ??
          (json['description'] as String? ?? '').split(',').first,
      secondaryText: structured?['secondary_text'] as String? ?? '',
      fullText: json['description'] as String? ?? '',
      placeId: json['place_id'] as String? ?? '',
    );
  }
}

class PlacesService {
  static const String _autocompleteBase =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String _detailsBase =
      'https://maps.googleapis.com/maps/api/place/details/json';

  final String _apiKey = AppConstants.googleMapsApiKey;

  Future<List<PlacePrediction>> getSuggestions(String input) async {
    final trimmed = input.trim();
    if (trimmed.length < 2) return [];

    final uri = Uri.parse(
      '$_autocompleteBase'
      '?input=${Uri.encodeComponent(trimmed)}'
      '&key=$_apiKey'
      '&components=country:lk'
      '&language=en',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final predictions = data['predictions'] as List<dynamic>? ?? [];
        return predictions
            .take(8)
            .map((p) => PlacePrediction.fromJson(p as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error getting place suggestions: $e');
    }
    return [];
  }

  Future<Map<String, double>?> getPlaceLocation(String placeId) async {
    if (placeId.isEmpty) return null;

    final uri = Uri.parse(
      '$_detailsBase'
      '?place_id=$placeId'
      '&fields=geometry'
      '&key=$_apiKey',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final loc =
            data['result']?['geometry']?['location'] as Map<String, dynamic>?;
        if (loc != null) {
          return {
            'lat': (loc['lat'] as num).toDouble(),
            'lng': (loc['lng'] as num).toDouble(),
          };
        }
      }
    } catch (e) {
      debugPrint('Error fetching place location: $e');
    }
    return null;
  }
}