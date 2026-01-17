import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum RouteTag { fastest, cheapest, quieter }

/// A chip that labels a route option for intelligent comparison.
class TLRouteTag extends StatelessWidget {
  final RouteTag tag;

  const TLRouteTag({super.key, required this.tag});

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
          Text(config.emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
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

  _TagConfig _getConfig() {
    switch (tag) {
      case RouteTag.fastest:
        return _TagConfig(
          emoji: '⚡',
          label: 'Fastest',
          color: const Color(0xFF1D4ED8),
          bgColor: const Color(0xFFDBEAFE),
        );
      case RouteTag.cheapest:
        return _TagConfig(
          emoji: '💰',
          label: 'Cheapest',
          color: const Color(0xFF16A34A),
          bgColor: const Color(0xFFDCFCE7),
        );
      case RouteTag.quieter:
        return _TagConfig(
          emoji: '🪑',
          label: 'Less Crowded',
          color: const Color(0xFF7C3AED),
          bgColor: const Color(0xFFEDE9FE),
        );
    }
  }
}

class _TagConfig {
  final String emoji;
  final String label;
  final Color color;
  final Color bgColor;
  _TagConfig({
    required this.emoji,
    required this.label,
    required this.color,
    required this.bgColor,
  });
}
