import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum BusStatus { arriving, delayed, full, onRoute }

class TLStatusBadge extends StatefulWidget {
  final BusStatus status;
  final String? delayMinutes;

  const TLStatusBadge({super.key, required this.status, this.delayMinutes});

  @override
  State<TLStatusBadge> createState() => _TLStatusBadgeState();
}

class _TLStatusBadgeState extends State<TLStatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.status == BusStatus.arriving) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: config.bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.status == BusStatus.arriving)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) => Opacity(
                opacity: _pulseAnim.value,
                child: Icon(config.icon, color: config.color, size: 10),
              ),
            )
          else
            Icon(config.icon, color: config.color, size: 10),
          const SizedBox(width: 5),
          Text(
            config.label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: config.color,
            ),
          ),
        ],
      ),
    );
  }

  _StatusConfig _getConfig() {
    switch (widget.status) {
      case BusStatus.arriving:
        return _StatusConfig(
          color: AppColors.liveGreen,
          bgColor: const Color(0xFFDCFCE7),
          icon: Icons.circle,
          label: 'Arriving',
        );
      case BusStatus.delayed:
        return _StatusConfig(
          color: AppColors.delayedAmber,
          bgColor: const Color(0xFFFEF3C7),
          icon: Icons.access_time_rounded,
          label: widget.delayMinutes != null
              ? 'Delayed ~${widget.delayMinutes}m'
              : 'Delayed',
        );
      case BusStatus.full:
        return _StatusConfig(
          color: AppColors.error,
          bgColor: const Color(0xFFFEE2E2),
          icon: Icons.people_rounded,
          label: 'Full',
        );
      case BusStatus.onRoute:
        return _StatusConfig(
          color: AppColors.primary,
          bgColor: const Color(0xFFDBEAFE),
          icon: Icons.directions_bus_rounded,
          label: 'On Route',
        );
    }
  }
}

class _StatusConfig {
  final Color color;
  final Color bgColor;
  final IconData icon;
  final String label;
  _StatusConfig({
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.label,
  });
}