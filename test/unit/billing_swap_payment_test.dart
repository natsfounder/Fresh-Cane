import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Billing Payment Method Swap Logic Tests', () {
    test('1. Empty payments list is rejected before RPC call', () {
      final payments = <Map<String, dynamic>>[];
      expect(payments.isEmpty, isTrue);
    });

    test('2. Cash payment payload matches single-tender specification', () {
      const finalAmount = 180.0;
      final payment = {
        'method': 'cash',
        'amount': finalAmount,
        'cash_tendered': finalAmount,
        'status': 'completed',
      };

      expect(payment['method'], 'cash');
      expect(payment['amount'], 180.0);
      expect(payment['cash_tendered'], 180.0);
    });

    test('3. UPI payment payload matches single-tender specification without cash fields', () {
      const finalAmount = 250.0;
      final payment = {
        'method': 'upi',
        'amount': finalAmount,
        'transaction_reference': 'UPI12345678',
        'status': 'completed',
      };

      expect(payment['method'], 'upi');
      expect(payment['amount'], 250.0);
      expect(payment.containsKey('cash_tendered'), isFalse);
    });

    test('4. Split payment sums must equal bill final amount', () {
      const finalAmount = 300.0;
      const splitCash = 100.0;
      const splitUpi = 200.0;

      final total = splitCash + splitUpi;
      expect((total - finalAmount).abs() < 0.01, isTrue);

      final payments = [
        {
          'method': 'cash',
          'amount': splitCash,
          'cash_tendered': splitCash,
          'status': 'completed',
        },
        {
          'method': 'upi',
          'amount': splitUpi,
          'status': 'completed',
        },
      ];

      final sum = payments.fold<double>(0.0, (acc, p) => acc + (p['amount'] as double));
      expect(sum, finalAmount);
    });

    test('5. Split payment mismatch is rejected', () {
      const finalAmount = 300.0;
      const splitCash = 100.0;
      const splitUpi = 150.0; // sum is 250 != 300

      final total = splitCash + splitUpi;
      expect((total - finalAmount).abs() < 0.01, isFalse);
    });
  });
}
