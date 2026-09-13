import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_cane/core/config/app_config.dart';
import 'package:fresh_cane/core/constants/app_constants.dart';

void main() {
  test('AppConfig and AppConstants definition smoke test', () {
    expect(AppConfig.appName, equals('Fresh Cane'));
    expect(AppConfig.supabaseUrl, isNotEmpty);
    expect(AppConfig.supabaseAnonKey, isNotEmpty);
    expect(AppConstants.storeSettingsSingletonId,
        equals('00000000-0000-0000-0000-000000000001'));
    expect(AppConstants.roleServer, equals('server'));
    expect(AppConstants.roleCashier, equals('cashier'));
    expect(AppConstants.roleSuperAdmin, equals('super_admin'));
  });
}
