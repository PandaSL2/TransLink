import 'package:flutter/material.dart';
import '../utils/app_localizations.dart';

class ErrorHandler {
  static String getFriendlyMessage(dynamic error, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return error.toString();

    final String msg = error.toString().toLowerCase();
    
    // Internet / Network Errors
    if (msg.contains('socketexception') || 
        msg.contains('failed host lookup') || 
        msg.contains('clientexception') ||
        msg.contains('no address associated') ||
        msg.contains('network') ||
        msg.contains('http') ||
        msg.contains('connection') ||
        msg.contains('os error')) {
      return l10n.translate('no_internet_msg');
    }

    // Timeout Errors
    if (msg.contains('timeoutexception') || 
        msg.contains('future not completed') || 
        msg.contains('0:00:15')) {
      return l10n.translate('timeout_msg');
    }

    // Auth Errors
    if (msg.contains('invalid login credentials') || 
        msg.contains('invalid_credentials')) {
      return l10n.translate('invalid_credentials');
    }

    // Permission Errors
    if (msg.contains('42501') || msg.contains('permission denied')) {
      return l10n.translate('permission_denied_msg');
    }

    // Database / Column errors
    if (msg.contains('fleet_type') || msg.contains('pgrst204')) {
      return 'System Update Required: Please update your app version.';
    }

    // Payment Errors
    if (msg.contains('insufficient balance')) {
      return l10n.translate('insufficient_balance_msg');
    }

    // Fallback
    return l10n.translate('something_went_wrong');
  }
}
