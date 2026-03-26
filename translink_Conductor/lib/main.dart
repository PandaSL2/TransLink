import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/driver_constants.dart';
import 'services/supabase_service.dart';
import 'services/location_service.dart';
import 'services/schedule_watch_service.dart';
import 'features/setup/setup_screen.dart';
import 'features/home/home_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/utils/app_localizations.dart';
import 'core/services/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await ScheduleWatchService.initialize();

  await SupabaseService.initialize();
  await LocationService.initializeService();

  final prefs = await SharedPreferences.getInstance();
  bool isLoggedIn = prefs.getBool(DriverConstants.keyIsLoggedIn) ?? false;

    if (SupabaseService.currentSession == null) {
      debugPrint('⏳ [AUTH] No active session on startup. Checking storage...');

      await SupabaseService.recoverSession();
    }
    debugPrint('✅ [AUTH] Starting app for ${isLoggedIn ? "logged-in" : "setup"} user.');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: TransLinkDriverApp(isLoggedIn: isLoggedIn),
    ),
  );
}

class TransLinkDriverApp extends StatelessWidget {
  final bool isLoggedIn;
  const TransLinkDriverApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return MaterialApp(
      title: 'TransLink Driver',
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      supportedLocales: const [Locale('en'), Locale('si'), Locale('ta')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Container(
        color: const Color(0xFFF1F5F9),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
              child: child!,
            ),
          ),
        ),
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
        ),
        textTheme: GoogleFonts.interTextTheme(),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      home: isLoggedIn ? const HomeScreen() : const SetupScreen(),
    );
  }
}