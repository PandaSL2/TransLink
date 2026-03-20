import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum AgeGroup {
  young,
  adult,
  senior,
}

class SavedPlace {
  final String name;
  final double lat;
  final double lng;

  const SavedPlace({required this.name, required this.lat, required this.lng});

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lng': lng};

  factory SavedPlace.fromJson(Map<String, dynamic> j) =>
      SavedPlace(name: j['name'] as String, lat: (j['lat'] as num).toDouble(), lng: (j['lng'] as num).toDouble());
}

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('en');
  String _mapStyle = 'Standard';
  bool _showVirtualBuses = true;
  bool _locationAutoDetect = true;
  bool _notificationsEnabled = true;

  AgeGroup _ageGroup = AgeGroup.adult;
  bool _ageSelected = false;

  SavedPlace? _homePlace;
  SavedPlace? _workPlace;

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  String get mapStyle => _mapStyle;
  bool get showVirtualBuses => _showVirtualBuses;
  bool get locationAutoDetect => _locationAutoDetect;
  bool get notificationsEnabled => _notificationsEnabled;
  AgeGroup get ageGroup => _ageGroup;
  bool get ageSelected => _ageSelected;
  SavedPlace? get homePlace => _homePlace;
  SavedPlace? get workPlace => _workPlace;

  double get textScaleFactor {
    switch (_ageGroup) {
      case AgeGroup.young:  return 1.0;
      case AgeGroup.adult:  return 1.05;
      case AgeGroup.senior: return 1.18;
    }
  }

  double get cardPaddingScale {
    switch (_ageGroup) {
      case AgeGroup.young:  return 1.0;
      case AgeGroup.adult:  return 1.0;
      case AgeGroup.senior: return 1.25;
    }
  }

  double get iconScale {
    switch (_ageGroup) {
      case AgeGroup.young:  return 1.0;
      case AgeGroup.adult:  return 1.0;
      case AgeGroup.senior: return 1.2;
    }
  }

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final themeStr = prefs.getString('theme_mode') ?? 'system';
    _themeMode = _getThemeModeFromString(themeStr);

    final lang = prefs.getString('language') ?? 'English';
    _locale = _getLocaleFromLanguage(lang);

    _mapStyle = prefs.getString('map_style') ?? 'Standard';
    _showVirtualBuses = prefs.getBool('show_buses') ?? true;
    _locationAutoDetect = prefs.getBool('location_auto') ?? true;
    _notificationsEnabled = prefs.getBool('notifications') ?? true;

    _ageSelected = prefs.getBool('age_selected') ?? false;
    final ageStr = prefs.getString('age_group') ?? 'adult';
    _ageGroup = _ageGroupFromString(ageStr);

    final homeJson = prefs.getString('home_place');
    if (homeJson != null) {
      try { _homePlace = SavedPlace.fromJson(json.decode(homeJson) as Map<String, dynamic>); } catch (_) {}
    }
    final workJson = prefs.getString('work_place');
    if (workJson != null) {
      try { _workPlace = SavedPlace.fromJson(json.decode(workJson) as Map<String, dynamic>); } catch (_) {}
    }

    notifyListeners();
  }

  AgeGroup _ageGroupFromString(String s) {
    switch (s) {
      case 'young':  return AgeGroup.young;
      case 'senior': return AgeGroup.senior;
      case 'adult':
      default:       return AgeGroup.adult;
    }
  }

  String _ageGroupToString(AgeGroup g) {
    switch (g) {
      case AgeGroup.young:  return 'young';
      case AgeGroup.senior: return 'senior';
      case AgeGroup.adult:  return 'adult';
    }
  }

  static AgeGroup ageGroupFromAge(int age) {
    if (age <= 30) {
      return AgeGroup.young;
    }
    if (age <= 45) {
      return AgeGroup.adult;
    }
    return AgeGroup.senior;
  }

  Future<void> setAgeGroup(AgeGroup group) async {
    _ageGroup = group;
    _ageSelected = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('age_group', _ageGroupToString(group));
    await prefs.setBool('age_selected', true);
    notifyListeners();
  }

  Future<void> setHomePlace(SavedPlace place) async {
    _homePlace = place;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_place', json.encode(place.toJson()));
    notifyListeners();
  }

  Future<void> setWorkPlace(SavedPlace place) async {
    _workPlace = place;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('work_place', json.encode(place.toJson()));
    notifyListeners();
  }

  Future<void> clearHomePlace() async {
    _homePlace = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('home_place');
    notifyListeners();
  }

  Future<void> clearWorkPlace() async {
    _workPlace = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('work_place');
    notifyListeners();
  }

  ThemeMode _getThemeModeFromString(String themeStr) {
    switch (themeStr) {
      case 'light': return ThemeMode.light;
      case 'dark':  return ThemeMode.dark;
      case 'system':
      default:      return ThemeMode.system;
    }
  }

  Locale _getLocaleFromLanguage(String lang) {
    switch (lang) {
      case 'සිංහල': return const Locale('si');
      case 'தமிழ்': return const Locale('ta');
      case 'English':
      default:       return const Locale('en');
    }
  }

  String get languageName {
    if (_locale.languageCode == 'si') {
      return 'සිංහල';
    }
    if (_locale.languageCode == 'ta') {
      return 'தமிழ்';
    }
    return 'English';
  }

  Future<void> setLanguage(String lang) async {
    _locale = _getLocaleFromLanguage(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    String themeStr = 'system';
    if (mode == ThemeMode.light) {
      themeStr = 'light';
    } else if (mode == ThemeMode.dark) {
      themeStr = 'dark';
    }
    await prefs.setString('theme_mode', themeStr);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    if (_themeMode == ThemeMode.light) {
      await setThemeMode(ThemeMode.dark);
    } else {
      await setThemeMode(ThemeMode.light);
    }
  }

  Future<void> setMapStyle(String style) async {
    _mapStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('map_style', style);
    notifyListeners();
  }

  Future<void> setVirtualBuses(bool value) async {
    _showVirtualBuses = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_buses', value);
    notifyListeners();
  }

  Future<void> setLocationAutoDetect(bool value) async {
    _locationAutoDetect = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('location_auto', value);
    notifyListeners();
  }

  Future<void> setNotifications(bool value) async {
    _notificationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications', value);
    notifyListeners();
  }
}