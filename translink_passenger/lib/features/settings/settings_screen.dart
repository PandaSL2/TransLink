import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/settings_provider.dart';
import '../../core/utils/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.translate('settings'), style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _sectionHeader(l10n.translate('map_location'), theme),
          _settingsCard([
            _switchTile(
              icon: Icons.my_location_rounded,
              title: l10n.translate('auto_detect'),
              subtitle: l10n.translate('auto_detect_sub'),
              value: settings.locationAutoDetect,
              onChanged: (v) => settings.setLocationAutoDetect(v),
              theme: theme,
            ),
            _divider(theme),
            _switchTile(
              icon: Icons.directions_bus_rounded,
              title: l10n.translate('show_virtual_buses'),
              subtitle: l10n.translate('show_virtual_buses_sub'),
              value: settings.showVirtualBuses,
              onChanged: (v) => settings.setVirtualBuses(v),
              theme: theme,
            ),
            _divider(theme),
            _dropdownTile(
              icon: Icons.map_rounded,
              title: l10n.translate('map_style'),
              value: settings.mapStyle,
              options: const ['Standard', 'Satellite (OSM)', 'Minimal'],
              onChanged: (v) { if (v != null) settings.setMapStyle(v); },
              theme: theme,
            ),
          ], theme),

          const SizedBox(height: 24),
          _sectionHeader(l10n.translate('notifications'), theme),
          _settingsCard([
            _switchTile(
              icon: Icons.notifications_rounded,
              title: l10n.translate('bus_arrival_alerts'),
              subtitle: l10n.translate('bus_arrival_alerts_sub'),
              value: settings.notificationsEnabled,
              onChanged: (v) => settings.setNotifications(v),
              theme: theme,
            ),
          ], theme),

          const SizedBox(height: 24),
          _sectionHeader(l10n.translate('app'), theme),
          _settingsCard([
            _dropdownTile(
              icon: Icons.dark_mode_rounded,
              title: 'Appearance',
              value: settings.themeMode == ThemeMode.light ? 'Light' : settings.themeMode == ThemeMode.dark ? 'Dark' : 'System Default',
              options: const ['System Default', 'Light', 'Dark'],
              onChanged: (v) {
                if (v == 'Light') settings.setThemeMode(ThemeMode.light);
                else if (v == 'Dark') settings.setThemeMode(ThemeMode.dark);
                else settings.setThemeMode(ThemeMode.system);
              },
              theme: theme,
            ),
            _divider(theme),
            _dropdownTile(
              icon: Icons.language_rounded,
              title: l10n.translate('language'),
              value: settings.languageName,
              options: const ['English', 'සිංහල', 'தமிழ்'],
              onChanged: (v) { if (v != null) settings.setLanguage(v); },
              theme: theme,
            ),
            _divider(theme),
            _actionTile(
              icon: Icons.info_outline_rounded,
              title: l10n.translate('about_translink'),
              subtitle: 'Version 1.2.0 Modern UX',
              onTap: () => _showCustomAboutDialog(context, theme),
              theme: theme,
            ),
          ], theme),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'TransLink Premium · Sri Lanka',
              style: GoogleFonts.inter(color: theme.textTheme.bodySmall?.color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showCustomAboutDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.directions_bus_rounded, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Text('TransLink', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('v1.2.0 Premium Re-design', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 12),
            Text(
              '© 2026 TransLink.lk\nNext-gen Public Transport System.',
              style: GoogleFonts.inter(fontSize: 13, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12),
    child: Text(title.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: theme.colorScheme.primary, letterSpacing: 1.2)),
  );

  Widget _settingsCard(List<Widget> children, ThemeData theme) => Container(
    decoration: BoxDecoration(
      color: theme.cardColor, 
      borderRadius: BorderRadius.circular(20), 
      border: Border.all(color: theme.dividerColor),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
    ),
    child: Column(children: children),
  );

  Widget _divider(ThemeData theme) => Divider(height: 1, indent: 60, endIndent: 16, color: theme.dividerColor);

  Widget _switchTile({required IconData icon, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged, required ThemeData theme}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: theme.colorScheme.primary, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
        ])),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }

  Widget _dropdownTile({required IconData icon, required String title, required String value, required List<String> options, required ValueChanged<String?> onChanged, required ThemeData theme}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: theme.colorScheme.primary, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700))),
        DropdownButton<String>(
          value: value,
          underline: const SizedBox(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
        ),
      ]),
    );
  }

  Widget _actionTile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap, required ThemeData theme}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: theme.colorScheme.primary, size: 20),
      ),
      title: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
