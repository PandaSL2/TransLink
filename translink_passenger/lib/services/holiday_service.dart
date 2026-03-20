import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translink_passenger/models/bus_models.dart';
import '../core/constants/app_constants.dart';
import 'supabase_service.dart';

class HolidayService {
  static final HolidayService _instance = HolidayService._internal();
  factory HolidayService() => _instance;
  HolidayService._internal();

  static const String _cacheKey = 'translink_holidays';
  Set<String> _holidayDates = {};

  Future<void> init() async {
    await _loadFromCache();
    await _fetchAndSync(DateTime.now().year);
  }

  bool isHoliday(DateTime date) {
    final key = _dateKey(date);
    return _holidayDates.contains(key);
  }

  Future<void> _fetchAndSync(int year) async {
    try {
      final url = Uri.parse(
        '${AppConstants.holidayApiBase}/PublicHolidays/$year/${AppConstants.countryCode}',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final holidays = data
            .map((e) => HolidayModel.fromJson(e as Map<String, dynamic>))
            .toList();

        _holidayDates = holidays.map((h) => _dateKey(h.holidayDate)).toSet();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(_holidayDates.toList()));

        final rows = holidays.map((h) => {
              'holiday_date': _dateKey(h.holidayDate),
              'name': h.name,
              'country_code': AppConstants.countryCode,
              'year': h.holidayDate.year,
            }).toList();
        await SupabaseService.upsertHolidays(rows);
      }
    } catch (_) {

    }
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      _holidayDates = (jsonDecode(cached) as List).cast<String>().toSet();
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}