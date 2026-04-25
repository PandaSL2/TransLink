import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/bus_models.dart';
import '../features/home/home_screen.dart';
import '../features/map/map_screen.dart';
import '../features/favourites/favourites_screen.dart';
import '../features/account/account_screen.dart';
import '../core/utils/app_localizations.dart';
import 'package:provider/provider.dart';
import '../providers/ride_provider.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  MainShellState createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0; // Home
  final GlobalKey<MapScreenState> _mapScreenKey = GlobalKey<MapScreenState>();
  final GlobalKey<AccountScreenState> _accountScreenKey = GlobalKey<AccountScreenState>();
  
  // Draggable Pill state
  Offset _pillPosition = const Offset(20, 0); // X follows left constraint, Y from bottom
  bool _isPillInitialized = false;

  void setTab(int index, {dynamic argument}) {
    setState(() => _currentIndex = index);
    
    // Defer execution until frame is rendered to ensure currentState is attached
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (index == 1 && _mapScreenKey.currentState != null) {
        if (argument != null && argument is TripModel) {
          _mapScreenKey.currentState!.handleNewTripFromHome(argument);
        } else {
          // restoreFromPrefs removed as per cleanup
        }
      }
      // If navigating to Account tab and QR flag is set
      if (index == 3 && argument == 'openQR') {
        _accountScreenKey.currentState?.openPaymentQR();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rideProvider = Provider.of<RideProvider>(context);
    
    final pages = <Widget>[
      const HomeScreen(),
      MapScreen(key: _mapScreenKey),
      const FavouritesScreen(),
      AccountScreen(key: _accountScreenKey),
    ];

    if (!_isPillInitialized) {
      // Default to near bottom-right
      _pillPosition = Offset(20, MediaQuery.of(context).size.height - 180);
      _isPillInitialized = true;
    }

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        
        // Custom logic: If on Map tab and search is active, clear search first
        if (_currentIndex == 1 && _mapScreenKey.currentState != null) {
          final cleared = _mapScreenKey.currentState!.tryClearSearch();
          if (cleared) return; // Handled, don't change tab
        }

        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: pages),
          if (rideProvider.isRideActive && _currentIndex != 1)
            Positioned(
              left: _pillPosition.dx,
              top: _pillPosition.dy,
              child: Draggable(
                feedback: Material(
                  color: Colors.transparent,
                  child: _buildRidePill(rideProvider),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: _buildRidePill(rideProvider)),
                onDragUpdate: (details) {
                  setState(() {
                    _pillPosition += details.delta;
                    // Clamp to screen bounds
                    final screen = MediaQuery.of(context).size;
                    _pillPosition = Offset(
                      _pillPosition.dx.clamp(0.0, screen.width - 250),
                      _pillPosition.dy.clamp(MediaQuery.of(context).padding.top, screen.height - 150),
                    );
                  });
                },
                child: _buildRidePill(rideProvider),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    ),
    );
  }

  Widget _buildRidePill(RideProvider rideProvider) {
    return GestureDetector(
      onTap: () => setTab(1),
      child: Container(
        width: 240,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ride in Progress - ${rideProvider.activeRoute?.routeNumber ?? ""}',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.drag_indicator_rounded, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final l10n = AppLocalizations.of(context)!;
    
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded, l10n.translate('home_nav')),
              _buildNavItem(1, Icons.explore_rounded, l10n.translate('explore_nav')),
              _buildNavItem(2, Icons.favorite_rounded, l10n.translate('saved_nav')),
              _buildNavItem(3, Icons.person_rounded, l10n.translate('account_nav')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _currentIndex == index;
    final color = isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).textTheme.bodySmall?.color;
    
    return GestureDetector(
      onTap: () => setTab(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            if (isActive) ...[
              const SizedBox(width: 8),
              Text(label, style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.2,
              )),
            ],
          ],
        ),
      ),
    );
  }
}
