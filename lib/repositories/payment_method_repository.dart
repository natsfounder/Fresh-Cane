import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_method_model.dart';
import '../services/supabase_service.dart';

class PaymentMethodRepository {
  final SupabaseClient _client;

  PaymentMethodRepository([SupabaseClient? client])
      : _client = client ?? SupabaseService.client;

  /// Fetch all configured payment methods (both enabled and disabled)
  Future<List<PaymentMethodItem>> fetchPaymentMethods() async {
    try {
      final response = await _client
          .from('payment_methods')
          .select('*')
          .order('display_order', ascending: true);

      if (response.isNotEmpty) {
        return response
            .map((item) => PaymentMethodItem.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      return PaymentMethodItem.defaultMethods;
    } catch (_) {
      // Return safe defaults if offline or table not yet configured
      return PaymentMethodItem.defaultMethods;
    }
  }

  /// Toggle enabled status of a payment method
  Future<void> togglePaymentMethod(String id, bool isEnabled) async {
    try {
      await _client.from('payment_methods').upsert({
        'id': id,
        'is_enabled': isEnabled,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // In offline/fallback mode, caller state is updated
    }
  }

  /// Update display name of a payment method
  Future<void> updatePaymentMethodName(String id, String name) async {
    try {
      await _client.from('payment_methods').upsert({
        'id': id,
        'name': name.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }
}
