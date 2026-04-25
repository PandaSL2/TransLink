import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('en');
  String _mapStyle = 'Standard';
  bool _showVirtualBuses = true;
  bool _locationAutoDetect = true;
  bool _notificationsEnabled = true;

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  String get mapStyle => _mapStyle;
  bool get showVirtualBuses => _showVirtualBuses;
  bool get locationAutoDetect => _locationAutoDetect;
  bool get notificationsEnabled => _notificationsEnabled;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Theme
    final themeStr = prefs.getString('theme_mode') ?? 'system';
    _themeMode = _getThemeModeFromString(themeStr);

    // Load Language
    final lang = prefs.getString('language') ?? 'English';
    _locale = _getLocaleFromLanguage(lang);

    // Load Map & Location
    _mapStyle = prefs.getString('map_style') ?? 'Standard';
    _showVirtualBuses = prefs.getBool('show_buses') ?? true;
    _locationAutoDetect = prefs.getBool('location_auto') ?? true;
    _notificationsEnabled = prefs.getBool('notifications') ?? true;

    notifyListeners();
  }

  ThemeMode _getThemeModeFromString(String themeStr) {
    switch (themeStr) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      case 'system':
      default: return ThemeMode.system;
    }
  }

  Locale _getLocaleFromLanguage(String lang) {
    switch (lang) {
      case 'සිංහල': return const Locale('si');
      case 'தமிழ்': return const Locale('ta');
      case 'English':
      default: return const Locale('en');
    }
  }

  String get languageName {
    if (_locale.languageCode == 'si') return 'සිංහල';
    if (_locale.languageCode == 'ta') return 'தமிழ்';
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
    if (mode == ThemeMode.light) themeStr = 'light';
    else if (mode == ThemeMode.dark) themeStr = 'dark';
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
