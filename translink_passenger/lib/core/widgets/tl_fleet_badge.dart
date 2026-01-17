import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum FleetType { ctb, private }

/// A small pill badge showing fleet type (CTB or Private) and bus count.
/// Per design system: use ONLY for fleet indicators — never as a large fill.
class TLFleetBadge extends StatelessWidget {
  final FleetType type;
  final int count;

  const TLFleetBadge({super.key, required this.type, required this.count});

  @override
  Widget build(BuildContext context) {
    final isCtb = type == FleetType.ctb;
    final color = isCtb ? AppColors.ctbRed : AppColors.privateBlue;
    final bgColor = isCtb ? const Color(0xFFFFEBEE) : const Color(0xFFE3F2FD);
    final label = isCtb ? 'CTB' : 'Private';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus_rounded, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            '$label ×$count',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
