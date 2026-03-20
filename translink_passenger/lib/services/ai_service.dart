import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiService {

  static const _apiKey = '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';
  static const _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'llama-3.1-8b-instant';

  static Future<List<String>> getSuggestions({
    required String rawQuery,
    required List<String> availableStops,
  }) async {
    if (rawQuery.trim().length < 2) return [];

    final stopList = availableStops.take(60).join(', ');

    try {
      final key = await getApiKey();
      final resp = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content':
                'You are a Sri Lanka bus route search assistant. '
                'Given a partial search query, return the 4 most likely matching bus stop or destination names from the provided list. '
                'Fix typos, understand Sinhala-romanized names, and handle common abbreviations. '
                'Available stops: $stopList. '
                'Reply with ONLY a JSON array of strings, no explanation. Example: ["Maharagama","Pettah","Direct"]',
            },
            {
              'role': 'user',
              'content': 'Query: "$rawQuery"',
            },
          ],
          'max_tokens': 100,
          'temperature': 0.2,
        }),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final content = data['choices'][0]['message']['content'] as String;

        final trimmed = content.trim();
        final start = trimmed.indexOf('[');
        final end = trimmed.lastIndexOf(']');
        if (start == -1 || end == -1) return _localFallback(rawQuery, availableStops);
        final list = jsonDecode(trimmed.substring(start, end + 1)) as List;
        return list.cast<String>().where((s) => s.isNotEmpty).take(4).toList();
      }
    } catch (_) {}
    return _localFallback(rawQuery, availableStops);
  }

  static Future<String> interpretQuery(String naturalQuery, List<String> stops) async {
    if (naturalQuery.trim().isEmpty) return naturalQuery;
    final stopList = stops.take(50).join(', ');

    try {
      final key = await getApiKey();
      final resp = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content':
                'Extract the destination from this bus route query for Sri Lanka. '
                'Return ONLY the destination name (1-3 words), nothing else. '
                'Available stops: $stopList',
            },
            {'role': 'user', 'content': naturalQuery},
          ],
          'max_tokens': 20,
          'temperature': 0.1,
        }),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final result = (data['choices'][0]['message']['content'] as String).trim();
        if (result.length < 40) return result;
      }
    } catch (_) {}
    return naturalQuery;
  }

  static String _customApiKey = _apiKey;
  static bool _loaded = false;

  static Future<String> getApiKey() async {
    if (!_loaded) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('groq_api_key');
      if (saved != null && saved.isNotEmpty) {
        _customApiKey = saved;
      }
      _loaded = true;
    }
    return _customApiKey;
  }

  static Future<void> saveApiKey(String key) async {
    _customApiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('groq_api_key', key);
  }

  static Future<String> chat({
    required String userMessage,
    required List<Map<String, String>> history,
    String language = 'English',
    List<RouteModel> routes = const [],
    List<StopModel> stops = const [],
  }) async {
    try {
      final routeContext = routes.take(10).map((r) => '${r.routeNumber}: ${r.name}').join(', ');
      final stopContext = stops.take(20).map((s) => s.name).join(', ');

      final messages = [
        {
          'role': 'system',
          'content': 'You are TransLink AI, a professional transit assistant for Sri Lanka. '
              'Your mission is to provide clear, direct, and authoritative information about bus routes, fares, and schedules. '
              'AVAILABLE CONTEXT: Routes: $routeContext. Stops: $stopContext. '
              'CRITICAL INSTRUCTIONS: '
              '1. YOU MUST RESPOND EXCLUSIVELY IN THE FOLLOWING LANGUAGE: **$language**. '
              '2. TONE: Be professional, polite, and clear. Avoid casual or "kid-like" talk. '
              '3. FORMATTING: Use plain text with clear bullet points. DO NOT use stars (**) for bolding or any Markdown that makes the text look cluttered. '
              '4. EMOJIS: Use emojis very sparingly—only at the start of a response to greet or indicate a bus. '
              '5. FARE DATA: Base fare is Rs. 40.00 for the first 2km, then Rs. 10.00 per km.',
        },
        ...history,
      ];

      final resp = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $_customApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'messages': messages,
          'temperature': 0.7,
        }),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['choices'][0]['message']['content'] as String;
      }
      return 'Error: AI service returned ${resp.statusCode}';
    } catch (e) {
      return 'Error: Could not connect to AI service.';
    }
  }

  static List<String> _localFallback(String query, List<String> stops) {
    final q = query.toLowerCase();
    final scored = <MapEntry<String, int>>[];
    for (final s in stops) {
      final sl = s.toLowerCase();
      if (sl.startsWith(q) || sl.contains(q)) {
        scored.add(MapEntry(s, 0));
      } else {
        final d = _levenshtein(q, sl.length > q.length + 3 ? sl.substring(0, q.length + 3) : sl);
        if (d <= 3) scored.add(MapEntry(s, d));
      }
    }
    scored.sort((a, b) => a.value.compareTo(b.value));
    return scored.take(4).map((e) => e.key).toList();
  }

  static int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (int j = 0; j <= n; j++) {
      dp[0][j] = j;
    }
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1]
            : 1 + [dp[i-1][j], dp[i][j-1], dp[i-1][j-1]].reduce((a,b) => a<b?a:b);
      }
    }
    return dp[m][n];
  }
}