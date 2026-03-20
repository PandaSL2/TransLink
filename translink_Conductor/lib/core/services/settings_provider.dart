import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  String get languageName {
    switch (_locale.languageCode) {
      case 'si': return 'සිංහල';
      case 'ta': return 'தமிழ்';
      default: return 'English';
    }
  }

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('language') ?? 'en';
    _locale = Locale(lang);
    notifyListeners();
  }

  Future<void> setLanguage(String name) async {
    String code = 'en';
    if (name == 'සිංහල') code = 'si';
    if (name == 'தமிழ்') code = 'ta';

    _locale = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', code);
    notifyListeners();
  }
}