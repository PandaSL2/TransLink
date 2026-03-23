import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _editing = false;
  final _nameCtrl = TextEditingController();

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
          _nameCtrl.text = data['full_name'] as String? ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      await _client.from('profiles').update({'full_name': _nameCtrl.text.trim()}).eq('id', uid);
      setState(() { _editing = false; _profile?['full_name'] = _nameCtrl.text.trim(); });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sign Out', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to sign out?', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _client.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _client.auth.currentUser;
    final role = _profile?['role'] as String? ?? 'passenger';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('My Profile', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => setState(() => _editing = true),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, const Color(0xFF1D4ED8)]),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 20, offset: const Offset(0, 8)
                      )
                    ],
                  ),
                  child: Center(
                    child: Text(
                      (_profile?['full_name'] as String? ?? 'P').substring(0, 1).toUpperCase(),
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _profile?['full_name'] as String? ?? 'Passenger',
                  style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(children: [
                    _infoRow(Icons.email_rounded, 'Email', user?.email ?? '-'),
                    Divider(height: 32, color: Theme.of(context).dividerColor),
                    if (_editing) ...[
                      TextField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: GoogleFonts.inter(),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel'))),
                        const SizedBox(width: 12),
                        Expanded(child: ElevatedButton(onPressed: _saveProfile, child: const Text('Save'))),
                      ]),
                    ] else
                      _infoRow(Icons.person_rounded, 'Full Name', _profile?['full_name'] as String? ?? '-'),
                    Divider(height: 32, color: Theme.of(context).dividerColor),
                    _infoRow(Icons.dataset_rounded, 'Account Type', role.toUpperCase()),
                    Divider(height: 32, color: Theme.of(context).dividerColor),
                    _infoRow(Icons.calendar_today_rounded, 'Member Since',
                      (_profile?['created_at'] as String?)?.split('T').first ?? '-'),
                  ]),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: Icon(Icons.logout_rounded, color: Theme.of(context).colorScheme.error),
                    label: Text('Sign Out Account', style: GoogleFonts.outfit(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
            Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).textTheme.bodyLarge?.color)),
          ]),
        ),
      ],
    );
  }
}