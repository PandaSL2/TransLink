import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:translink_driver/core/constants/driver_constants.dart';
import 'package:translink_driver/services/supabase_service.dart';

void main() {
  test('fetch routes', () async {
    await Supabase.initialize(
      url: DriverConstants.supabaseUrl,
      anonKey: DriverConstants.supabaseAnonKey,
    );
    print('running getAvailableRoutes');
    
    final routes = await SupabaseService.getAvailableRoutes();
    print('Found routes: ${routes.length}');
  });
}
