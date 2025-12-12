import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/utils/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../models/bus_models.dart';
import '../../services/ai_service.dart';
import '../../services/supabase_service.dart';
import '../../core/services/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  final List<Map<String, String>> _history = [];
  bool _loading = false;
  bool _apiKeyMissing = false;
  List<RouteModel> _routes = [];
  List<StopModel> _stops = [];
  late stt.SpeechToText _speechToText;
  bool _isListening = false;

  static const _prefsKey = 'ai_chat_history';
  static const _maxAgeHours = 24;

  static const _quickQuestions = [
    'What bus goes to Pettah?',
    'When does bus 128 run?',
    'How long from Homagama to Fort?',
    'Are buses running on Poya day?',
    'What are the bus fares?',
  ];

  @override
  void initState() {
    super.initState();
    _speechToText = stt.SpeechToText();
    _init();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadMessages();
    if (_messages.isEmpty) {
      _messages.add(_ChatMessage(
        text: '👋 Hi! I\'m TransLink AI. Ask me about bus routes, schedules, or travel tips in Sri Lanka!',
        isBot: true,
        timestamp: DateTime.now(),
      ));
      await _saveMessages();
    }

    final key = await AiService.getApiKey();
    if (key.isEmpty && mounted) setState(() => _apiKeyMissing = true);

    try {
      final r = await Future.wait([SupabaseService.getActiveRoutes(), SupabaseService.getAllStops()]);
      _routes = r[0] as List<RouteModel>;
      _stops  = r[1] as List<StopModel>;
    } catch (_) {}

    if (mounted) setState(() {});
  }

  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final List<dynamic> decoded = json.decode(raw);
      final cutoff = DateTime.now().subtract(const Duration(hours: _maxAgeHours));
      final persisted = decoded
          .map((e) => _ChatMessage.fromJson(e as Map<String, dynamic>))
          .where((m) => m.timestamp.isAfter(cutoff))
          .toList();

      if (persisted.isNotEmpty && mounted) {
        setState(() => _messages.addAll(persisted));
        for (final m in persisted) {
          _history.add({'role': m.isBot ? 'assistant' : 'user', 'content': m.text});
        }
      }
    } catch (e) {
      debugPrint('Chat load error: $e');
    }
  }

  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cutoff = DateTime.now().subtract(const Duration(hours: _maxAgeHours));
      final toSave = _messages.where((m) => m.timestamp.isAfter(cutoff)).toList();
      await prefs.setString(_prefsKey, json.encode(toSave.map((m) => m.toJson()).toList()));
    } catch (e) {
      debugPrint('Chat save error: $e');
    }
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _msgCtrl.text).trim();
    if (msg.isEmpty || _loading) return;
    _msgCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(text: msg, isBot: false, timestamp: DateTime.now()));
      _loading = true;
    });
    _scrollToBottom();
    await _saveMessages();

    _history.add({'role': 'user', 'content': msg});
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    
    final reply = await AiService.chat(
      userMessage: msg, 
      language: settings.languageName,
      history: _history, 
      routes: _routes, 
      stops: _stops,
    );
    _history.add({'role': 'assistant', 'content': reply});

    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(text: reply, isBot: true, timestamp: DateTime.now()));
        _loading = false;
      });
      await _saveMessages();
      _scrollToBottom();
    }
  }

  void _listen() async {
    if (!_isListening) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return;
      bool available = await _speechToText.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speechToText.listen(onResult: (val) => setState(() => _msgCtrl.text = val.recognizedWords));
      }
    } else {
      setState(() => _isListening = false);
      _speechToText.stop();
    }
  }

  void _clearChat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    setState(() {
      _messages.clear();
      _history.clear();
      _messages.add(_ChatMessage(
        text: '👋 Hi! I\'m TransLink AI. Ask me about bus routes, schedules, or travel tips in Sri Lanka!',
        isBot: true,
        timestamp: DateTime.now(),
      ));
    });
    await _saveMessages();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, const Color(0xFF1D4ED8)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Text('Assistant', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_loading ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _messages.length) return _buildTypingIndicator();
              return _msgBubble(_messages[i]);
            },
          ),
        ),
        if (_messages.length <= 1)
          Container(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _quickQuestions.map((q) => GestureDetector(
                onTap: () => _send(q),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
                  ),
                  child: Center(child: Text(q, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary))),
                ),
              )).toList(),
            ),
          ),
        _buildInputArea(),
      ]),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: _msgCtrl,
                decoration: const InputDecoration(hintText: 'Ask about buses...', border: InputBorder.none),
                style: GoogleFonts.inter(fontSize: 15),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: () => _send(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _msgBubble(_ChatMessage msg) {
    final isBot = msg.isBot;
    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isBot ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft: Radius.circular(isBot ? 4 : 24),
            bottomRight: Radius.circular(isBot ? 24 : 4),
          ),
          boxShadow: [
             BoxShadow(
               color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.05),
               blurRadius: 10,
               offset: const Offset(0, 4)
             )
          ],
          border: isBot ? Border.all(color: Theme.of(context).dividerColor) : null,
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Text(
          msg.text, 
          style: GoogleFonts.inter(
            fontSize: 15, 
            fontWeight: FontWeight.w600, 
            color: isBot ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onPrimary, 
            height: 1.5
          )
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [_dot(0), const SizedBox(width: 4), _dot(150), const SizedBox(width: 4), _dot(300)]),
      ),
    );
  }

  Widget _dot(int delay) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 600 + delay),
    builder: (_, v, _) => Container(
      width: 8, height: 8, 
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.4 + (0.6 * v)), shape: BoxShape.circle)
    ),
  );
}

class _ChatMessage {
  final String text;
  final bool isBot;
  final DateTime timestamp;
  _ChatMessage({required this.text, required this.isBot, required this.timestamp});
  factory _ChatMessage.fromJson(Map<String, dynamic> json) => _ChatMessage(text: json['text'], isBot: json['isBot'], timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts']));
  Map<String, dynamic> toJson() => {'text': text, 'isBot': isBot, 'ts': timestamp.millisecondsSinceEpoch};
}
