import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/payment_method_model.dart';
import '../repositories/payment_method_repository.dart';

final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>((ref) {
  return PaymentMethodRepository();
});

final paymentMethodsProvider =
    NotifierProvider<PaymentMethodsNotifier, List<PaymentMethodItem>>(() {
  return PaymentMethodsNotifier();
});

/// Direct provider that yields only the currently enabled payment methods
final enabledPaymentMethodsProvider = Provider<List<PaymentMethodItem>>((ref) {
  final all = ref.watch(paymentMethodsProvider);
  final enabled = all.where((m) => m.isEnabled).toList();
  // Ensure at least Cash and UPI exist if all disabled accidentally
  if (enabled.isEmpty) {
    return PaymentMethodItem.defaultMethods.where((m) => m.isEnabled).toList();
  }
  return enabled;
});

class PaymentMethodsNotifier extends Notifier<List<PaymentMethodItem>> {
  PaymentMethodRepository get _repo => ref.read(paymentMethodRepositoryProvider);

  @override
  List<PaymentMethodItem> build() {
    loadPaymentMethods();
    return PaymentMethodItem.defaultMethods;
  }

  Future<void> loadPaymentMethods() async {
    final list = await _repo.fetchPaymentMethods();
    state = list;
  }

  Future<void> toggleMethod(String id, bool isEnabled) async {
    state = state.map((m) {
      if (m.id == id) {
        return m.copyWith(isEnabled: isEnabled);
      }
      return m;
    }).toList();

    await _repo.togglePaymentMethod(id, isEnabled);
  }

  Future<void> updateName(String id, String newName) async {
    state = state.map((m) {
      if (m.id == id) {
        return m.copyWith(name: newName);
      }
      return m;
    }).toList();

    await _repo.updatePaymentMethodName(id, newName);
  }
}
