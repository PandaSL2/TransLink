import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/supabase_service.dart';

class LinkCardScreen extends StatefulWidget {
  const LinkCardScreen({super.key});

  @override
  State<LinkCardScreen> createState() => _LinkCardScreenState();
}

class _LinkCardScreenState extends State<LinkCardScreen> {
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cardNameController = TextEditingController();
  bool _isSaving = false;

  Future<void> _saveCard() async {
    if (_cardNumberController.text.length < 16) return;
    
    setState(() => _isSaving = true);
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 2));
    
    final cardData = {
      'card_last_4': _cardNumberController.text.substring(_cardNumberController.text.length - 4),
      'card_brand': _cardNumberController.text.startsWith('4') ? 'Visa' : 'MasterCard',
      'expiry_date': _expiryController.text,
      'is_default': true,
    };

    await SupabaseService.addPaymentCard(cardData);
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
         content: Text('Card Linked Successfully!'),
         backgroundColor: Color(0xFF10B981),
       ));
       Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Link Payment Card'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardPreview(),
            const SizedBox(height: 32),
            _inputField('Cardholder Name', _cardNameController, 'John Doe'),
            const SizedBox(height: 20),
            _inputField('Card Number', _cardNumberController, '0000 0000 0000 0000', 
              keyboard: TextInputType.number, 
              formatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
                _CardNumberFormatter(),
              ]),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _inputField('Expiry', _expiryController, 'MM/YY', 
                  keyboard: TextInputType.number,
                  formatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                    _ExpiryFormatter(),
                  ])),
                const SizedBox(width: 16),
                Expanded(child: _inputField('CVV', _cvvController, '***', keyboard: TextInputType.number, obscure: true)),
              ],
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveCard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isSaving 
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Text('Link Card Securely', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                const SizedBox(width: 8),
                Text('Secure 256-bit SSL Encryption', style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPreview() {
    return Container(
      width: double.infinity,
      height: 200,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.nfc_rounded, color: Colors.white70, size: 24),
              Text('Visa', style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          const Spacer(),
          Text(
            _cardNumberController.text.isEmpty ? '**** **** **** ****' : _cardNumberController.text,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CARD HOLDER', style: GoogleFonts.inter(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(_cardNameController.text.isEmpty ? 'FULL NAME' : _cardNameController.text.toUpperCase(),
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(width: 40),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('EXPIRES', style: GoogleFonts.inter(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(_expiryController.text.isEmpty ? 'MM/YY' : _expiryController.text,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, String hint, {TextInputType? keyboard, bool obscure = false, List<TextInputFormatter>? formatters}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodySmall?.color)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          obscureText: obscure,
          inputFormatters: formatters,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
          ),
        ),
      ],
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldV, TextEditingValue newV) {
    var text = newV.text.replaceAll(' ', '');
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length) {
        buffer.write(' ');
      }
    }
    var res = buffer.toString();
    return newV.copyWith(text: res, selection: TextSelection.collapsed(offset: res.length));
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldV, TextEditingValue newV) {
    var text = newV.text.replaceAll('/', '');
    if (text.length > 2) {
      text = '${text.substring(0, 2)}/${text.substring(2)}';
    }
    return newV.copyWith(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
