import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/billing_repository.dart';
import 'cashier_notifier.dart';
import 'cashier_state.dart';

/// Provider exposing BillingRepository singleton instance.
final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepository();
});

/// Riverpod NotifierProvider for Cashier POS workflow.
final cashierProvider =
    NotifierProvider<CashierNotifier, CashierState>(CashierNotifier.new);
