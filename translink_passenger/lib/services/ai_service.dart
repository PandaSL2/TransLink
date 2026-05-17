import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bus_models.dart';
import 'api_keys.dart';

class AiService {

  static const _apiKey = ApiKeys.openRouterKey;
  static const _openRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const _model = 'google/gemini-2.5-flash';

  static Future<List<String>> getSuggestions({
    required String rawQuery,
    required List<String> availableStops,
  }) async {
    if (rawQuery.trim().length < 2) return [];

    final stopList = availableStops.take(60).join(', ');

    try {
      final resp = await http.post(
        Uri.parse(_openRouterUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
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
      final resp = await http.post(
        Uri.parse(_openRouterUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
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

  static Future<String> chat({
    required String userMessage,
    required List<Map<String, String>> history,
    String language = 'English',
    List<RouteModel> routes = const [],
    List<StopModel> stops = const [],
    double? userLat,
    double? userLng,
  }) async {
    try {
      double balance = 0.0;
      List<Map<String, dynamic>> transactions = [];
      List<Map<String, dynamic>> liveBuses = [];
      String currentUserEmail = '';
      String currentUserId = '';
      String nearestStopName = 'Unknown';
      double nearestDistance = double.infinity;

      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          currentUserId = user.id;
          currentUserEmail = user.email ?? '';
        }
      } catch (_) {}

      try {
        final balanceRes = await Supabase.instance.client.from('passenger_wallets').select('balance').eq('user_id', currentUserId).maybeSingle();
        if (balanceRes != null) {
          balance = (balanceRes['balance'] as num).toDouble();
        }
      } catch (_) {}

      try {
        final txRes = await Supabase.instance.client.from('fare_transactions').select().eq('passenger_id', currentUserId).order('created_at', ascending: false).limit(5);
        transactions = (txRes as List).cast<Map<String, dynamic>>();
      } catch (_) {}

      try {
        final busRes = await Supabase.instance.client.from('live_bus_positions').select();
        liveBuses = (busRes as List).cast<Map<String, dynamic>>();
      } catch (_) {}

      if (userLat != null && userLng != null) {
        for (final stop in stops) {
          final dist = _haversineDistance(userLat, userLng, stop.lat, stop.lng);
          if (dist < nearestDistance) {
            nearestDistance = dist;
            nearestStopName = stop.name;
          }
        }
      }

      final dbContext = jsonEncode({
        'current_time': DateTime.now().toIso8601String(),
        'user': {
          'id': currentUserId,
          'email': currentUserEmail,
          'current_location': userLat != null && userLng != null ? {
            'latitude': userLat,
            'longitude': userLng,
            'nearest_stop': nearestStopName,
            'nearest_distance_meters': nearestDistance == double.infinity ? null : nearestDistance.round(),
          } : null,
        },
        'wallet': {
          'balance': balance,
        },
        'recent_transactions': transactions.map((t) => {
          'id': t['id'],
          'amount': t['amount'],
          'type': t['type'],
          'status': t['status'],
          'bus_number': t['bus_number'],
          'route_number': t['route_number'],
          'description': t['description'],
          'created_at': t['created_at'],
        }).toList(),
        'live_buses': liveBuses.map((b) => {
          'bus_number': b['bus_number'],
          'route_number': b['route_number'],
          'route_name': b['route_name'],
          'latitude': b['latitude'],
          'longitude': b['longitude'],
          'speed': b['speed'],
          'status': b['status'],
          'last_updated_at': b['last_updated_at'],
        }).toList(),
        'routes': routes.map((r) => {
          'route_number': r.routeNumber,
          'name': r.routeName,
        }).toList(),
        'stops': stops.map((s) => {
          'name': s.name,
          'latitude': s.lat,
          'longitude': s.lng,
        }).toList(),
      });

      final messages = [
        {
          'role': 'system',
          'content': 'You are TransLink AI, a premium, production-grade transit intelligence assistant for Sri Lanka. '
              'You have real-time access to the local database and the internet. '
              'If the user asks questions that require web search (e.g. weather, general info, holidays, general news, train schedules, or general internet questions), use your built-in Google Search/web search grounding capabilities or your internet knowledge to answer them accurately. '
              'If the query relates to the local transit database (e.g. their balance, transactions, routes, stops, live buses), consult the provided real-time database context. '
              'REAL-TIME DATABASE CONTEXT: $dbContext '
              'CRITICAL OUTPUT LAYOUT INSTRUCTIONS: '
              '1. LANGUAGE: Respond strictly in: **$language**. '
              '2. STRUCTURE: Always use highly concise, step-by-step point-form structures for route/bus queries. Never use dense, multi-sentence paragraphs. '
              '3. SPACING: Ensure there are double line breaks (\\n\\n) between distinct steps or points for a clean, spacious layout. '
              '4. FILLER: Keep conversational introduction/filler to an absolute minimum. Get straight to the steps! '
              '5. BOLDING: Use standard markdown double asterisks (`**`) strictly to highlight bus route numbers, specific stop names, or transaction amounts/balances (e.g., **Route 128**, **Thalagala**, **LKR 150**). The frontend will parse and style these. '
              '6. TONE: Professional, clean, and direct.',
        },
        ...history,
      ];

      final resp = await http.post(
        Uri.parse(_openRouterUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'messages': messages,
          'max_tokens': 1000,
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

  static double _haversineDistance(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) * math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
}