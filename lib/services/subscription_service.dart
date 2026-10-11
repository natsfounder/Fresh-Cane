import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'supabase_service.dart';

/// Provider holding the real-time software freeze status.
final softwareFrozenProvider = NotifierProvider<SoftwareFrozenNotifier, bool>(() {
  return SoftwareFrozenNotifier();
});

class SoftwareFrozenNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Check initial freeze status on app load
    checkFreezeStatus();
    return false;
  }

  /// Check software freeze status from Supabase
  Future<bool> checkFreezeStatus() async {
    try {
      final res = await SupabaseService.client.rpc('get_software_freeze_status');
      final isFrozen = res == true;
      state = isFrozen;
      return isFrozen;
    } catch (e) {
      debugPrint('Error checking freeze status: $e');
      return state;
    }
  }

  /// Set software freeze status (SuperAdmin control)
  Future<void> setFreezeStatus(bool frozen) async {
    try {
      final res = await SupabaseService.client.rpc(
        'set_software_frozen',
        params: {'p_frozen': frozen},
      );
      state = res == true;
    } catch (e) {
      debugPrint('Error updating freeze status: $e');
      rethrow;
    }
  }
}
