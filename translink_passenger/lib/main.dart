import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'features/auth/get_started_screen.dart';
import 'features/auth/login_screen.dart';
import 'services/holiday_service.dart';
import 'core/services/settings_provider.dart';
import 'core/utils/app_localizations.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui/main_shell.dart';
import 'core/services/notification_service.dart';
import 'providers/ride_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  
  debugPrint('Starting application. kIsWeb: $kIsWeb, platform: $defaultTargetPlatform');

  // Initialize Supabase
  try {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  } catch (e) {
    debugPrint('Supabase initialization failed: $e');
  }

  // Initialize holiday service
  try {
    await HolidayService().init();
  } catch (e) {
    debugPrint('Holiday service initialization failed: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => RideProvider()),
      ],
      child: const TransLinkApp(),
    ),
  );
}

class TransLinkApp extends StatelessWidget {
  const TransLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return MaterialApp(
      title: 'TransLink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: const [
        Locale('en'),
        Locale('si'),
        Locale('ta'),
      ],
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Container(
        color: Theme.of(context).scaffoldBackgroundColor, // Full-screen background
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      home: const _AppRouter(),
    );
  }
}


class _AppRouter extends StatefulWidget {
  const _AppRouter();

  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> {
  bool _isLoading = true;
  bool _showOnboarding = false;
  bool _showGetStarted = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // Check first time opening
    final prefs = await SharedPreferences.getInstance();
    final isFirstTime = prefs.getBool('is_first_time') ?? true;
    _showOnboarding = isFirstTime;

    // Check existing session
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      _showGetStarted = false;
      _isLoggedIn = true;
    }

    if (mounted) setState(() => _isLoading = false);

    // Listen for auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      switch (state.event) {
        case AuthChangeEvent.signedIn:
          setState(() { _isLoggedIn = true; _showGetStarted = false; });
          break;
        case AuthChangeEvent.signedOut:
          setState(() { _isLoggedIn = false; _showGetStarted = true; });
          break;
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_showOnboarding) {
      return OnboardingScreen(
        onFinish: () => setState(() => _showOnboarding = false),
      );
    }
    
    if (_isLoggedIn) {
      return const MainShell();
    }
    
    if (_showGetStarted) {
      return GetStartedScreen(
        onGetStarted: () => setState(() => _showGetStarted = false),
      );
    }
    
    return LoginScreen(
      onLoggedIn: () => setState(() => _isLoggedIn = true),
    );
  }
}
