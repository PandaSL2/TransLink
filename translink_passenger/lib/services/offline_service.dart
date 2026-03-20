import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_models.dart';

class OfflineService {
  static const String _starredRoutesKey = 'starred_routes_v2';

  static Future<void> starRoute(AiDiscoveredRoute route) async {
    final prefs = await SharedPreferences.getInstance();
    final starred = await getStarredRoutes();

    if (starred.any((r) => r.id == route.id)) return;

    starred.add(route);
    await prefs.setString(_starredRoutesKey, json.encode(starred.map((r) => r.toJson()).toList()));
  }

  static Future<void> unstarRoute(String routeId) async {
    final prefs = await SharedPreferences.getInstance();
    final starred = await getStarredRoutes();
    starred.removeWhere((r) => r.id == routeId);
    await prefs.setString(_starredRoutesKey, json.encode(starred.map((r) => r.toJson()).toList()));
  }

  static Future<List<AiDiscoveredRoute>> getStarredRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_starredRoutesKey);
    if (data == null) return [];

    try {
      final List<dynamic> list = json.decode(data);
      return list.map((json) => AiDiscoveredRoute.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<bool> isStarred(String routeId) async {
    final starred = await getStarredRoutes();
    return starred.any((r) => r.id == routeId);
  }
}