import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Admin Dashboard Payment Breakdown Parsing Tests', () {
    test('Correctly extracts values from updated RPC payload format', () {
      final updatedPayload = [
        {
          'payment_method': 'cash',
          'total_amount': 1500.50,
          'transaction_count': 12,
        },
        {
          'payment_method': 'upi',
          'total_amount': 3200.00,
          'transaction_count': 25,
        },
      ];

      final totalAmount = updatedPayload.fold<double>(
        0.0,
        (sum, p) => sum + (((p['total_amount'] ?? p['amount']) as num?)?.toDouble() ?? 0.0),
      );

      expect(totalAmount, 4700.50);

      final first = updatedPayload[0];
      final method1 = (first['payment_method'] ?? first['method'] ?? 'cash').toString().toUpperCase();
      final amount1 = ((first['total_amount'] ?? first['amount']) as num?)?.toDouble() ?? 0.0;
      final count1 = ((first['transaction_count'] ?? first['count']) as num?)?.toInt() ?? 0;

      expect(method1, 'CASH');
      expect(amount1, 1500.50);
      expect(count1, 12);

      final second = updatedPayload[1];
      final method2 = (second['payment_method'] ?? second['method'] ?? 'cash').toString().toUpperCase();
      final amount2 = ((second['total_amount'] ?? second['amount']) as num?)?.toDouble() ?? 0.0;
      final count2 = ((second['transaction_count'] ?? second['count']) as num?)?.toInt() ?? 0;

      expect(method2, 'UPI');
      expect(amount2, 3200.00);
      expect(count2, 25);
    });

    test('Maintains backward compatibility with legacy RPC payload format', () {
      final legacyPayload = [
        {
          'method': 'cash',
          'amount': 500.0,
          'count': 3,
        },
      ];

      final totalAmount = legacyPayload.fold<double>(
        0.0,
        (sum, p) => sum + (((p['total_amount'] ?? p['amount']) as num?)?.toDouble() ?? 0.0),
      );

      expect(totalAmount, 500.0);

      final item = legacyPayload[0];
      final method = (item['payment_method'] ?? item['method'] ?? 'cash').toString().toUpperCase();
      final amount = ((item['total_amount'] ?? item['amount']) as num?)?.toDouble() ?? 0.0;
      final count = ((item['transaction_count'] ?? item['count']) as num?)?.toInt() ?? 0;

      expect(method, 'CASH');
      expect(amount, 500.0);
      expect(count, 3);
    });
  });
}
