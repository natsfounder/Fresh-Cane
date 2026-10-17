import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_cane/models/settlement_model.dart';

void main() {
  group('SettlementDailySummary - Accounting Integrity & Zero-Only Overrides', () {
    final testDate = DateTime(2026, 10, 11);

    test('1. Zero-only eligibility flags accurately reflect natural ledger zero', () {
      // Natural zero scenario
      final zeroSummary = SettlementDailySummary(
        date: testDate,
        openingCash: 0.0,
        openingUpi: 0.0,
        salesCash: 0.0,
        salesUpi: 0.0,
        expensesCash: 0.0,
        expensesUpi: 0.0,
      );

      expect(zeroSummary.openingTotal, 0.0);
      expect(zeroSummary.closingTotal, 0.0);
      expect(zeroSummary.canEnterManualOpening, isTrue);
      expect(zeroSummary.canEnterManualClosing, isTrue);

      // Non-zero opening scenario (prior sales occurred)
      final nonZeroOpening = SettlementDailySummary(
        date: testDate,
        openingCash: 450.0,
        openingUpi: 150.0,
        salesCash: 200.0,
        salesUpi: 0.0,
        expensesCash: 50.0,
        expensesUpi: 0.0,
      );

      expect(nonZeroOpening.openingTotal, 600.0);
      expect(nonZeroOpening.canEnterManualOpening, isFalse);
      expect(nonZeroOpening.closingTotal, 750.0);
      expect(nonZeroOpening.canEnterManualClosing, isFalse);
    });

    test('2. Non-zero calculated balances STRICTLY reject manual overrides', () {
      // If a database row or direct API call supplied manual values for a non-zero day,
      // the model strictly preserves the natural calculated values.
      final nonZeroWithOverride = SettlementDailySummary(
        date: testDate,
        openingCash: 500.0,
        openingUpi: 200.0,
        salesCash: 300.0,
        salesUpi: 100.0,
        expensesCash: 100.0,
        expensesUpi: 50.0,
        manualOpeningCash: 9999.0, // Attempted unauthorized override
        manualOpeningUpi: 8888.0,
        openingReason: 'Unauthorized tampering attempt',
      );

      expect(nonZeroWithOpeningOverrideSafe(nonZeroWithOverride), isTrue);
      // Effective values MUST remain the natural calculated values:
      expect(nonZeroWithOverride.effectiveOpeningCash, 500.0);
      expect(nonZeroWithOverride.effectiveOpeningUpi, 200.0);
      expect(nonZeroWithOverride.effectiveOpeningTotal, 700.0);
      expect(nonZeroWithOverride.effectiveClosingCash, 500.0 + 300.0 - 100.0); // 700.0
      expect(nonZeroWithOverride.effectiveClosingUpi, 200.0 + 100.0 - 50.0);   // 250.0
      expect(nonZeroWithOverride.effectiveClosingTotal, 950.0);
    });

    test('3. Manual opening float updates effective closing balance accurately when natural opening is zero', () {
      final summaryWithFloat = SettlementDailySummary(
        date: testDate,
        openingCash: 0.0,
        openingUpi: 0.0,
        salesCash: 280.0,
        salesUpi: 120.0,
        expensesCash: 150.0,
        expensesUpi: 0.0,
        manualOpeningCash: 1000.0, // Petty cash float in drawer
        manualOpeningUpi: 0.0,
        openingReason: 'Morning petty cash drawer float',
      );

      expect(summaryWithFloat.canEnterManualOpening, isTrue);
      expect(summaryWithFloat.hasManualOpening, isTrue);
      expect(summaryWithFloat.effectiveOpeningCash, 1000.0);
      expect(summaryWithFloat.effectiveOpeningUpi, 0.0);
      expect(summaryWithFloat.effectiveOpeningTotal, 1000.0);

      // Effective Closing = Effective Opening + Sales - Expenses
      // Cash: 1000 + 280 - 150 = 1130
      // UPI: 0 + 120 - 0 = 120
      // Total: 1130 + 120 = 1250
      expect(summaryWithFloat.effectiveClosingCash, 1130.0);
      expect(summaryWithFloat.effectiveClosingUpi, 120.0);
      expect(summaryWithFloat.effectiveClosingTotal, 1250.0);

      // Raw ledger values remain untouched:
      expect(summaryWithFloat.openingCash, 0.0);
      expect(summaryWithFloat.openingTotal, 0.0);
      expect(summaryWithFloat.closingCash, 130.0);
      expect(summaryWithFloat.closingTotal, 250.0);
    });

    test('4. Mathematical Consistency: Cash + UPI + Other == Total across all calculations', () {
      final complexSummary = SettlementDailySummary(
        date: testDate,
        openingCash: 0.0,
        openingUpi: 0.0,
        openingOther: 0.0,
        salesCash: 350.50,
        salesUpi: 420.75,
        salesOther: 25.00,
        expensesCash: 120.25,
        expensesUpi: 50.00,
        expensesOther: 10.00,
        manualOpeningCash: 500.0,
        manualOpeningUpi: 100.0,
        openingReason: 'Verified starting float',
      );

      // Opening Consistency
      expect(
        complexSummary.effectiveOpeningTotal,
        complexSummary.effectiveOpeningCash + complexSummary.effectiveOpeningUpi + complexSummary.effectiveOpeningOther,
      );

      // Sales Consistency
      expect(
        complexSummary.salesTotal,
        complexSummary.salesCash + complexSummary.salesUpi + complexSummary.salesOther,
      );

      // Expenses Consistency
      expect(
        complexSummary.expensesTotal,
        complexSummary.expensesCash + complexSummary.expensesUpi + complexSummary.expensesOther,
      );

      // Net Movement Consistency
      expect(
        complexSummary.netTotal,
        complexSummary.netCash + complexSummary.netUpi + complexSummary.netOther,
      );

      // Closing Consistency
      expect(
        complexSummary.effectiveClosingTotal,
        complexSummary.effectiveClosingCash + complexSummary.effectiveClosingUpi + complexSummary.effectiveClosingOther,
      );
    });

    test('5. Audit metadata fields are preserved intact', () {
      final now = DateTime.now();
      final auditedSummary = SettlementDailySummary(
        date: testDate,
        openingCash: 0.0,
        openingUpi: 0.0,
        manualOpeningCash: 1500.0,
        openingReason: 'Approved petty cash injection',
        overrideUpdatedBy: 'b31baaef-3096-4476-b5c0-3c739a2b5b24',
        overrideUpdatedAt: now,
      );

      expect(auditedSummary.openingReason, 'Approved petty cash injection');
      expect(auditedSummary.overrideUpdatedBy, 'b31baaef-3096-4476-b5c0-3c739a2b5b24');
      expect(auditedSummary.overrideUpdatedAt, now);
    });

    test('6. Option A: Automated Carry-Forward of yesterday closing into today opening (12-Oct & 13-Oct scenario)', () {
      // Day 1 (12-Oct-2026): Initial float established by Super Admin
      final day1 = SettlementDailySummary(
        date: DateTime(2026, 10, 12),
        openingCash: 0.0,
        openingUpi: 0.0,
        manualOpeningCash: 12700.0,
        manualOpeningUpi: 61071.0,
        openingReason: 'starting',
        salesCash: 6310.0,
        salesUpi: 5090.0,
        expensesCash: 5610.0,
        expensesUpi: 4160.0,
      );

      expect(day1.effectiveOpeningCash, 12700.0);
      expect(day1.effectiveOpeningUpi, 61071.0);
      expect(day1.effectiveOpeningTotal, 73771.0);
      expect(day1.effectiveClosingCash, 13400.0); // 12700 + 6310 - 5610
      expect(day1.effectiveClosingUpi, 62001.0);  // 61071 + 5090 - 4160
      expect(day1.effectiveClosingTotal, 75401.0);

      // Day 2 (13-Oct-2026): Carry-Forward calculates opening from baseline + Day 1 movements
      // openingCash = 12700 + (6310 - 5610) = 13400
      // openingUpi = 61071 + (5090 - 4160) = 62001
      final day2 = SettlementDailySummary(
        date: DateTime(2026, 10, 13),
        openingCash: day1.effectiveClosingCash, // 13400.0 automatically carried forward
        openingUpi: day1.effectiveClosingUpi,   // 62001.0 automatically carried forward
        salesCash: 0.0,
        salesUpi: 0.0,
        expensesCash: 0.0,
        expensesUpi: 0.0,
      );

      // Verify Day 2 opening is identical to Day 1 closing
      expect(day2.effectiveOpeningCash, day1.effectiveClosingCash);
      expect(day2.effectiveOpeningUpi, day1.effectiveClosingUpi);
      expect(day2.effectiveOpeningTotal, day1.effectiveClosingTotal);
      expect(day2.effectiveOpeningTotal, 75401.0);

      // Day 2 closing also defaults to 75401.0 before any new transactions occur
      expect(day2.effectiveClosingCash, 13400.0);
      expect(day2.effectiveClosingUpi, 62001.0);
      expect(day2.effectiveClosingTotal, 75401.0);

      // Crucially, Day 2 cannot be manually overridden because calculated opening is already ₹75,401
      expect(day2.canEnterManualOpening, isFalse);
    });

    test('7. Option A: Multi-day continuous cascade into Day 3 upon Day 2 new transactions', () {
      // Day 2 transactions occur: +2,000 cash sales, -500 cash expenses
      const day2OpeningCash = 13400.0;
      const day2OpeningUpi = 62001.0;
      final day2WithActivity = SettlementDailySummary(
        date: DateTime(2026, 10, 13),
        openingCash: day2OpeningCash,
        openingUpi: day2OpeningUpi,
        salesCash: 2000.0,
        salesUpi: 1500.0,
        expensesCash: 500.0,
        expensesUpi: 0.0,
      );

      expect(day2WithActivity.effectiveClosingCash, 14900.0); // 13400 + 2000 - 500
      expect(day2WithActivity.effectiveClosingUpi, 63501.0);  // 62001 + 1500
      expect(day2WithActivity.effectiveClosingTotal, 78401.0);

      // Day 3 (14-Oct-2026) automatically opens with Day 2 closing balance
      final day3 = SettlementDailySummary(
        date: DateTime(2026, 10, 14),
        openingCash: day2WithActivity.effectiveClosingCash,
        openingUpi: day2WithActivity.effectiveClosingUpi,
      );

      expect(day3.effectiveOpeningCash, 14900.0);
      expect(day3.effectiveOpeningUpi, 63501.0);
      expect(day3.effectiveOpeningTotal, 78401.0);
    });
  });
}

bool nonZeroWithOpeningOverrideSafe(SettlementDailySummary summary) {
  return !summary.canEnterManualOpening &&
      summary.effectiveOpeningTotal == summary.openingTotal;
}
