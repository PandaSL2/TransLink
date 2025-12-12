import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/settings_provider.dart';
import '../../core/utils/app_localizations.dart';
import '../../services/supabase_service.dart';
import '../wallet/link_card_screen.dart';
import '../ai/ai_chat_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  AccountScreenState createState() => AccountScreenState();
}

class AccountScreenState extends State<AccountScreen> {
  final _client = Supabase.instance.client;
  final FlutterTts _flutterTts = FlutterTts();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _editingName = false;
  final _nameCtrl = TextEditingController();
  String? _cachedQrData;
  final GlobalKey _historyKey = GlobalKey();

  /// Called externally (e.g. from Pay Fare button on home tab)
  void openPaymentQR() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showPaymentQR();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      
      final data = await _client.from('profiles').select().eq('id', uid).single();
      
      if (mounted) {
        setState(() {
        _profile = data;
        
        // 1. Try metadata first (from signup)
        final meta = _client.auth.currentUser?.userMetadata;
        final metaName = meta?['full_name'] as String? ?? '';
        
        if (metaName.isNotEmpty && metaName != 'Passenger') {
          _nameCtrl.text = metaName;
        } else {
          // 2. Try stored profile
          final stored = data['full_name'] as String? ?? '';
          final email = _client.auth.currentUser?.email ?? '';
          _nameCtrl.text = (stored.isEmpty || stored == 'Passenger')
              ? email.split('@').first
              : stored;
        }
        _loading = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      
      // Update the profiles table
      await _client.from('profiles').update({'full_name': name}).eq('id', uid);
      
      // Update the auth user metadata (for MapScreen header)
      await _client.auth.updateUser(UserAttributes(data: {'full_name': name}));
      
      if (mounted) {
        setState(() { _editingName = false; _profile?['full_name'] = name; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.translate('username_updated')), backgroundColor: AppColors.accent));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.translate('something_went_wrong')}: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _signOut() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.translate('sign_out'), style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(l10n.translate('are_you_sure'), style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.translate('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: Text(l10n.translate('sign_out')),
          ),
        ],
      ),
    );
    if (ok == true) await _client.auth.signOut();
  }

  Future<void> _speakBalance(double balance) async {
    final lang = AppLocalizations.of(context)!.locale.languageCode;
    String text = "";
    if (lang == 'si') {
      text = "ඔබේ පසුම්බියේ ශේෂය රුපියල් ${balance.toStringAsFixed(0)} රුපියල් වේ.";
    } else if (lang == 'ta') {
      text = "உங்கள் பணப்பையின் இருப்பு ${balance.toStringAsFixed(0)} ரூபாய்.";
    } else {
      text = "Your current wallet balance is ${balance.toStringAsFixed(0)} rupees.";
    }
    await _flutterTts.setLanguage(lang == 'si' ? 'si-LK' : (lang == 'ta' ? 'ta-IN' : 'en-US'));
    await _flutterTts.speak(text);
  }

  Future<void> _showPaymentQR() async {
    if (_cachedQrData == null) {
      final prefs = await SharedPreferences.getInstance();
      final activeJson = prefs.getString('active_route');
      String pickup = "Unknown";
      String drop = "Unknown";
      double fare = 30.0;

      if (activeJson != null) {
        try {
          final data = json.decode(activeJson);
          pickup = data['pickup_stop'] ?? "Unknown";
          drop = data['routeName'] ?? "Destination";
          fare = 45.0;
        } catch (_) {}
      }

      _cachedQrData = jsonEncode({
        "userId": SupabaseService.client.auth.currentUser?.id,
        "type": "payment_qr",
        "session": "sess_${DateTime.now().millisecondsSinceEpoch}",
      });
    }

    if (!mounted) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PaymentQR',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        final l10n = AppLocalizations.of(context)!;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Center(
            child: ScaleTransition(
              scale: anim1,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.4 : 0.1),
                        blurRadius: 30, offset: const Offset(0, 10)
                      )
                    ],
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.translate('scan_to_pay'), 
                        style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(height: 8),
                      Text(l10n.translate('show_to_conductor'), 
                        style: GoogleFonts.inter(color: Theme.of(context).textTheme.bodySmall?.color, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Theme.of(context).dividerColor, width: 2),
                        ),
                        child: QrImageView(
                          data: _cachedQrData!,
                          version: QrVersions.auto,
                          size: 200.0,
                          foregroundColor: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          child: Text(l10n.translate('close_btn'), 
                            style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPassTypeSelection(AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            Text(l10n.translate('select_pass_type'), style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 24),
            _passItem(l10n, Icons.school_rounded, l10n.translate('school_pass'), 'For students with valid school ID'),
            const SizedBox(height: 12),
            _passItem(l10n, Icons.train_rounded, l10n.translate('train_pass'), 'Monthly unlimited train travel'),
          ],
        ),
      ),
    );
  }

  Widget _passItem(AppLocalizations l10n, IconData icon, String title, String sub) {
    return InkWell(
      onTap: () {
        Navigator.pop(context); // Close selection
        _simulatePassPurchase(l10n, title);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
                Text(sub, style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _simulatePassPurchase(AppLocalizations l10n, String type) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Theme.of(context).cardColor,
        title: Text(l10n.translate('buy_pass_btn'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        content: Text('Confirm purchase of $type?', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(l10n.translate('cancel'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('$type registered successfully!'),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary, 
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }

  void _showTopUpOptions(AppLocalizations l10n) async {
    final cards = await SupabaseService.getPaymentCards();
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 44, height: 5, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 24),
            Text(
              l10n.translate('top_up_method'),
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.card_membership_rounded, color: Theme.of(context).colorScheme.secondary, size: 22),
              ),
              title: Text(
                l10n.translate('passes_title'),
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
              ),
              subtitle: Text('School & Train season passes', style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () {
                Navigator.pop(ctx);
                _showPassTypeSelection(l10n);
              },
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            if (cards.isEmpty)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.add_card_rounded, color: Theme.of(context).colorScheme.primary, size: 22),
                ),
                title: Text(
                  l10n.translate('link_new_card'),
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                ),
                subtitle: Text('Credit / Debit card', style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LinkCardScreen()));
                },
              )
            else
              ...cards.map((c) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                  child: Icon(c['card_brand'] == 'Visa' ? Icons.credit_card : Icons.credit_card_off, color: Theme.of(context).colorScheme.secondary, size: 22),
                ),
                title: Text('**** **** **** ${c['card_last_4']}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: AppColors.error.withOpacity(0.7), size: 22),
                  onPressed: () async {
                    await SupabaseService.deletePaymentCard(c['id'].toString());
                    if (mounted) {
                      Navigator.pop(ctx);
                      _showTopUpOptions(l10n);
                    }
                  },
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showManualTopUpDialog();
                },
              )),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.qr_code_2_rounded, color: Colors.orange, size: 22),
              ),
              title: Text('LankaQR (Primary)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
              subtitle: Text('Scan at any station or agent', style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () {
                Navigator.pop(ctx);
                _showLankaQRModal(l10n);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLankaQRModal(AppLocalizations l10n) {
    final uid = _client.auth.currentUser?.id ?? 'guest';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_2, color: Colors.orange, size: 40),
                const SizedBox(width: 12),
                Text('LankaQR Top-up', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Show this QR to any authorized TransLink agent or scan with your banking app to top up instantly.', 
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.orange.withOpacity(0.5), width: 2),
                boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.1), blurRadius: 20)],
              ),
              child: QrImageView(
                data: 'LANKAQR:TRANSLINK:WALLET:$uid',
                version: QrVersions.auto,
                size: 200.0,
                foregroundColor: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _showManualTopUpDialog(),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white),
                child: const Text('MANUAL TOP-UP'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualTopUpDialog() {
    final controller = TextEditingController(text: '500');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Top Up Wallet', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter amount to top up:', style: GoogleFonts.inter(fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: 'Rs. ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.secondary, width: 2)),
              ),
              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final amt = double.tryParse(controller.text) ?? 0.0;
              if (amt > 0) {
                Navigator.pop(ctx);
                _simulateTopUp(amt);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _simulateTopUp(double amount) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: AppColors.secondary)),
    );

    try {
      await SupabaseService.topUpWallet(amount);
      if (mounted) {
        Navigator.pop(context); // Close loader
        // Success notification
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Rs. ${amount.toStringAsFixed(0)} added to wallet!'),
          backgroundColor: AppColors.accent,
        ));
        // REFETCH BALANCE IMMEDIATELY
        _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final errorStr = e.toString();
        final l10n = AppLocalizations.of(context)!;
        if (errorStr.contains('SocketException') || errorStr.contains('Failed host lookup')) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('no_internet_msg')), backgroundColor: AppColors.error));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l10n.translate('something_went_wrong')}: $e'), backgroundColor: AppColors.error));
        }
      }
    }
  }

  void _scrollToRecentActivity() {
    Scrollable.ensureVisible(_historyKey.currentContext!, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
  }

  String get _displayName {
    // 1. Try metadata (where we save it in LoginScreen)
    final meta = _client.auth.currentUser?.userMetadata;
    final metaName = meta?['full_name'] as String? ?? '';
    if (metaName.isNotEmpty && metaName != 'Passenger') return metaName;

    // 2. Try profile table
    final stored = _profile?['full_name'] as String? ?? '';
    if (stored.isNotEmpty && stored != 'Passenger') return stored;

    // 3. Fallback to email
    final email = _client.auth.currentUser?.email ?? '';
    return email.split('@').first;
  }

  String get _joinedDate {
    final raw = _profile?['created_at'] as String?;
    if (raw == null) return '-';
    return raw.split('T').first;
  }

  String get _role => _profile?['role'] as String? ?? 'passenger';

  @override
  Widget build(BuildContext context) {
    final email = _client.auth.currentUser?.email ?? '-';
    final settings = Provider.of<SettingsProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.translate('account_nav')),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.secondary))
          : StreamBuilder<double>(
              stream: SupabaseService.getWalletStream(),
              builder: (context, balanceSnapshot) {
                final balance = balanceSnapshot.data ?? 0.0;
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: SupabaseService.getTransactionsStream(),
                  builder: (context, txSnapshot) {
                    if (txSnapshot.connectionState == ConnectionState.waiting && !txSnapshot.hasData) {
                      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.secondary));
                    }
                    final transactions = txSnapshot.data ?? [];
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      children: [
                        // ── Profile Header ─────────────────────────────
                        const SizedBox(height: 16),
                        _buildProfileHeader(l10n),
                        const SizedBox(height: 24),

                        // ── Wallet Section ─────────────────────────────
                        _sectionLabel(l10n.translate('wallet_title')),
                        _buildWalletBalanceCard(l10n, balance),
                        const SizedBox(height: 24),

                        // ── Recent Activity ───────────────────────────
                        _sectionHeader(l10n.translate('recent_activity'), transactions, key: _historyKey),
                        _buildTransactionList(l10n, transactions, txSnapshot.connectionState == ConnectionState.waiting),
                        const SizedBox(height: 24),

                        // ── Account Settings ──────────────────────────
                        _sectionLabel(l10n.translate('account_nav')),
                        _card([
                          _infoTile(Icons.email_outlined, l10n.translate('email_address'), email),
                          _divider(),
                          if (_editingName) ...[
                            _buildNameEditFields(l10n),
                          ] else
                            _infoTile(Icons.person_outline_rounded, l10n.translate('full_name'), _displayName),
                          _divider(),
                          _infoTile(Icons.badge_outlined, l10n.translate('role'), _role[0].toUpperCase() + _role.substring(1)),
                          _divider(),
                          _infoTile(Icons.calendar_today_outlined, l10n.translate('member_since'), _joinedDate),
                        ]),
                        const SizedBox(height: 24),

                        // ── Map & App Settings ─────────────────────────
                        _sectionLabel(l10n.translate('settings')),
                        _card([
                          _switchTile(Icons.directions_bus_rounded, l10n.translate('show_virtual_buses'), l10n.translate('show_virtual_buses_sub'),
                            settings.showVirtualBuses, (v) { settings.setVirtualBuses(v); }),
                          _divider(),
                          _switchTile(Icons.my_location_rounded, l10n.translate('auto_detect'), l10n.translate('auto_detect_sub'),
                            settings.locationAutoDetect, (v) { settings.setLocationAutoDetect(v); }),
                          _divider(),
                          _dropdownTile(Icons.map_rounded, l10n.translate('map_style'), settings.mapStyle,
                            ['Standard', 'Satellite (OSM)', 'Minimal'],
                            (v) { if (v != null) { settings.setMapStyle(v); } },
                            itemLabels: {
                              'Standard': l10n.translate('style_standard'),
                              'Satellite (OSM)': l10n.translate('style_satellite'),
                              'Minimal': l10n.translate('style_minimal'),
                            }),
                          _divider(),
                          ListTile(
                            leading: Icon(Icons.info_outline_rounded, color: Theme.of(context).colorScheme.secondary, size: 20),
                            title: Text(l10n.translate('about_translink'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(context).textTheme.bodyLarge?.color)),
                            trailing: Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                            onTap: () => _showCustomAboutDialog(context),
                          ),
                        ]),
                        const SizedBox(height: 32),

                        // ── Sign Out ─────────────────────────────────
                        _signOutButton(l10n),
                      ],
                    );
                  }
                );
              }
            ),
    );
  }

  Widget _buildProfileHeader(AppLocalizations l10n) {
    return Row(
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary]),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (Theme.of(context).brightness == Brightness.dark ? Colors.black : AppColors.primary).withOpacity(0.3), 
                blurRadius: 12, 
                offset: const Offset(0, 4)
              )
            ],
          ),
          child: Center(child: Text(
            _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'P',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
          )),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_displayName, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiary.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text(_role.toUpperCase(), style: GoogleFonts.inter(color: Theme.of(context).colorScheme.tertiary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.translate('verified_account'), style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.edit_note_rounded, color: Theme.of(context).colorScheme.secondary),
          onPressed: () => setState(() => _editingName = true),
        ),
      ],
    );
  }

  Widget _buildWalletBalanceCard(AppLocalizations l10n, double balance) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).cardColor : null,
        gradient: isDark ? null : LinearGradient(
          colors: [Theme.of(context).colorScheme.primary, const Color(0xFF1D4ED8)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(isDark ? 0.4 : 0.25), 
            blurRadius: 25, 
            offset: const Offset(0, 12)
          )
        ],
        border: isDark ? Border.all(color: Theme.of(context).dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.translate('available_balance').toUpperCase(), 
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.6), letterSpacing: 1.5)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                child: GestureDetector(
                  onTap: () => _speakBalance(balance),
                  child: const Icon(Icons.volume_up_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Rs. ', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.secondary)),
              Text(balance.toStringAsFixed(2), style: GoogleFonts.outfit(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showTopUpOptions(l10n),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(l10n.translate('top_up').toUpperCase()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                    textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AiChatScreen()));
                  },
                  icon: const Icon(Icons.mic_rounded, size: 18),
                  label: Text(l10n.translate('voice_assist').toUpperCase()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.12),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: Colors.white.withOpacity(0.15)),
                    textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildTransactionList(AppLocalizations l10n, List<Map<String, dynamic>> txs, bool loading) {
    if (loading && txs.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 3, color: Theme.of(context).colorScheme.primary)));
    if (txs.isEmpty) {
      return _card([
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Icon(Icons.history_rounded, color: Theme.of(context).dividerColor, size: 48),
            const SizedBox(height: 12),
            Text('No recent transactions', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]);
    }

    return _card(
      txs.take(4).map((tx) {
        final isDebit = (tx['type'] == 'debit' || tx['type'] == 'fare' || tx['type'] == 'fare_deduction');
        final amount = (tx['amount'] as num).toDouble();
        final dateStr = tx['created_at'] as String?;
        final date = dateStr != null ? DateTime.parse(dateStr).toLocal() : DateTime.now();

        return Column(
          children: [
            ListTile(
              onTap: () => _showTransactionDetails(tx, l10n),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isDebit ? AppColors.error : AppColors.accent).withOpacity(0.08), 
                  shape: BoxShape.circle
                ),
                child: Icon(isDebit ? Icons.remove_rounded : Icons.add_rounded, 
                  color: isDebit ? AppColors.error : AppColors.accent, size: 18),
              ),
              title: Text(tx['description'] ?? 'Transport Fare', 
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
              subtitle: Text('${date.day}/${date.month} • ${date.hour}:${date.minute.toString().padLeft(2, '0')}', 
                style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${isDebit ? "-" : "+"} Rs.${amount.toStringAsFixed(0)}', 
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 16, 
                      color: isDebit ? Theme.of(context).colorScheme.onSurface : AppColors.accent)),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, size: 18, color: Theme.of(context).dividerColor),
                ],
              ),
            ),
            if (tx != txs.take(4).last) Divider(height: 1, indent: 68, color: Theme.of(context).dividerColor),
          ],
        );
      }).toList(),
    );
  }

  void _showTransactionDetails(Map<String, dynamic> tx, AppLocalizations l10n) {
    final amount = (tx['amount'] as num).toDouble();
    final isDebit = (tx['type'] == 'debit' || tx['type'] == 'fare' || tx['type'] == 'fare_deduction');
    final dateStr = tx['created_at'] as String?;
    final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();
    final busNum = tx['bus_number'] ?? 'N/A';
    final routeNum = tx['route_number'] ?? '—';
    final startStop = tx['start_stop'] ?? 'Pickup Point';
    final endStop = tx['end_stop'] ?? 'Destination';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Transaction Details', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                    Text("ID: ${tx['id'].toString().substring(0, 8).toUpperCase()}", style: GoogleFonts.inter(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: (isDebit ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary).withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(isDebit ? Icons.receipt_long_rounded : Icons.account_balance_wallet_rounded, color: isDebit ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary, size: 24),
                ),
              ],
            ),
            const Divider(height: 48),
            
            // Route Visualizer (Simple)
            if (isDebit) ...[
              Row(
                children: [
                   Column(
                     children: [
                       const Icon(Icons.radio_button_checked, color: Color(0xFFD97706), size: 16),
                       Container(width: 2, height: 40, color: Theme.of(context).dividerColor),
                       Icon(Icons.location_on, color: Theme.of(context).colorScheme.error, size: 16),
                     ],
                   ),
                   const SizedBox(width: 16),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text(startStop, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
                         const SizedBox(height: 24),
                         Text(endStop, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
                       ],
                     ),
                   ),
                ],
              ),
              const SizedBox(height: 32),
            ],

            // Info Grid
            Row(
              children: [
                _detailBlock('BUS NO.', busNum, Icons.directions_bus_rounded),
                const SizedBox(width: 24),
                _detailBlock('ROUTE', routeNum, Icons.route_rounded),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _detailBlock('DATE', "${date.toLocal().day.toString().padLeft(2, '0')}/${date.toLocal().month.toString().padLeft(2, '0')}/${date.toLocal().year}", Icons.calendar_today_rounded),
                const SizedBox(width: 24),
                _detailBlock('TIME', "${date.toLocal().hour.toString().padLeft(2, '0')}:${date.toLocal().minute.toString().padLeft(2, '0')}", Icons.access_time_rounded),
              ],
            ),

            const Divider(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Amount', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text("Rs. ${amount.toStringAsFixed(2)}", style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, foregroundColor: Theme.of(context).colorScheme.onSurface, elevation: 0),
                child: const Text('BACK'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailBlock(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, List<Map<String, dynamic>> txs, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title.toUpperCase(), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
          GestureDetector(
            onTap: () {
              if (txs.isNotEmpty) {
                _showAllTransactionsDialog(txs);
              }
            },
            child: Text('SEE ALL', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  void _showAllTransactionsDialog(List<Map<String, dynamic>> txs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('Transaction history'.toUpperCase(), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 24),
            Builder(
              builder: (ctx) {
                final l10n = AppLocalizations.of(ctx)!;
                return Expanded(
                  child: ListView.separated(
                    itemCount: txs.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final tx = txs[i];
                      final isDebit = (tx['type'] == 'debit' || tx['type'] == 'fare' || tx['type'] == 'fare_deduction');
                      final amount = (tx['amount'] as num).toDouble();
                      final dateStr = tx['created_at'] as String?;
                      final date = dateStr != null ? DateTime.parse(dateStr).toLocal() : DateTime.now();
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: (isDebit ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary).withOpacity(0.1), shape: BoxShape.circle),
                          child: Icon(isDebit ? Icons.remove_rounded : Icons.add_rounded, color: isDebit ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary, size: 20),
                        ),
                        title: Text(tx['description'] ?? 'Transport Fare', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                        subtitle: Text('${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}', style: GoogleFonts.inter(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        trailing: Text("${isDebit ? '-' : '+'} Rs. ${amount.toStringAsFixed(0)}", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: isDebit ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.primary)),
                      );
                    },
                  ),
                );
              }
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameEditFields(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Icon(Icons.person_outline_rounded, color: Theme.of(context).colorScheme.secondary, size: 20),
          const SizedBox(width: 12),
          Expanded(child: TextField(
            controller: _nameCtrl, autofocus: true,
            decoration: InputDecoration(labelText: l10n.translate('full_name'), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            style: GoogleFonts.inter(fontSize: 14),
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => setState(() => _editingName = false), child: Text(l10n.translate('cancel')))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(onPressed: _saveName, child: Text(l10n.translate('save')))),
        ]),
      ]),
    );
  }

  Widget _signOutButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: OutlinedButton.icon(
        onPressed: _signOut,
        icon: Icon(Icons.logout_rounded, color: Theme.of(context).colorScheme.error.withOpacity(0.8), size: 20),
        label: Text(l10n.translate('sign_out'), 
          style: GoogleFonts.inter(color: Theme.of(context).colorScheme.error.withOpacity(0.8), fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Theme.of(context).colorScheme.error.withOpacity(0.2), width: 1.5),
          backgroundColor: Theme.of(context).colorScheme.error.withOpacity(0.04), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
      color: Theme.of(context).textTheme.bodySmall?.color, letterSpacing: 0.5)),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).dividerColor)),
    child: Column(children: children),
  );

  Widget _divider() => Divider(height: 1, indent: 56, color: Theme.of(context).dividerColor);

  Widget _infoTile(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.inter(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color)),
              Text(value, style: GoogleFonts.inter(fontSize: 14, color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _switchTile(IconData icon, String title, String sub, bool value, ValueChanged<bool> cb) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(children: [
      Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 20),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(context).textTheme.bodyLarge?.color)),
        Text(sub, style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
      ])),
      Switch(value: value, onChanged: cb, activeThumbColor: Theme.of(context).colorScheme.secondary),
    ]),
  );

  Widget _dropdownTile(IconData icon, String title, String value, List<String> opts, ValueChanged<String?> cb, {Map<String, String>? itemLabels}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 20),
      const SizedBox(width: 14),
      Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(context).textTheme.bodyLarge?.color))),
      DropdownButton<String>(
        value: value, underline: const SizedBox(),
        dropdownColor: Theme.of(context).cardColor,
        style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.secondary),
        items: opts.map((o) => DropdownMenuItem(value: o, child: Text(itemLabels?[o] ?? o, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)))).toList(),
        onChanged: cb,
      ),
    ]),
  );

  void _showCustomAboutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.directions_bus_rounded, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 10),
            const Text('TransLink', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translate('version'), style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            Text(
              '© 2026 TransLink.lk\nLocation-Aware Predictive Public Transport System for Sri Lanka.',
              style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text(
              'Developed to enhance the passenger experience with real-time tracking and smart route discovery.',
              style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('close'), style: GoogleFonts.inter(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
