import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/app_localizations.dart';

class FareCalculatorSheet extends StatefulWidget {
  const FareCalculatorSheet({super.key});

  @override
  State<FareCalculatorSheet> createState() => _FareCalculatorSheetState();
}

class _FareCalculatorSheetState extends State<FareCalculatorSheet> {
  String _amount = '0';

  void _onKeyTap(String key) {
    setState(() {
      if (key == 'C') {
        _amount = '0';
      } else if (key == '⌫') {
        if (_amount.length > 1) {
          _amount = _amount.substring(0, _amount.length - 1);
        } else {
          _amount = '0';
        }
      } else {
        if (_amount == '0') {
          _amount = key;
        } else {
          _amount += key;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Text(l10n.translate('manual_entry_title') ?? 'Manual Fare Entry', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Rs. ', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                Text(_amount, style: GoogleFonts.outfit(fontSize: 48, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              for (var i = 1; i <= 9; i++) _calcButton(i.toString()),
              _calcButton('C', color: Colors.redAccent),
              _calcButton('0'),
              _calcButton('⌫', color: Colors.orangeAccent),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _amount == '0' ? null : () => Navigator.pop(context, double.tryParse(_amount)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(l10n.translate('collect_fare') ?? 'Collect Fare', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calcButton(String label, {Color? color}) {
    return InkWell(
      onTap: () => _onKeyTap(label),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: (color ?? const Color(0xFFF8FAFC)).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: (color ?? const Color(0xFFE2E8F0)).withOpacity(0.3)),
        ),
        alignment: Alignment.center,
        child: Text(label, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: color ?? const Color(0xFF1E293B))),
      ),
    );
  }
}
