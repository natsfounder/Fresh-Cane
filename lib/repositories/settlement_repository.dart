import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/settlement_model.dart';
import '../services/supabase_service.dart';

class SettlementRepository {
  final SupabaseClient _client;

  SettlementRepository([SupabaseClient? client])
      : _client = client ?? SupabaseService.client;

  /// Fetch and compute Daily Settlement for a given date.
  /// Calculation: Opening Balance + Sales − Expenses = Closing Balance
  /// Handled automatically based on transaction timestamps (NO MANUAL "CLOSE DAY").
  Future<({
    SettlementDailySummary summary,
    List<SettlementTransactionItem> transactions,
  })> fetchDailySettlement(DateTime targetDate) async {
    try {
      final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // 1. Fetch completed payments (sales)
      final paymentsResponse = await _client
          .from('payments')
          .select('id, amount, payment_method, status, transaction_reference, created_at, bills(bill_number)')
          .eq('status', 'completed')
          .order('created_at', ascending: true);

      // 2. Fetch completed expenses
      final expensesResponse = await _client
          .from('expense_transactions')
          .select('id, expense_name_snapshot, amount, payment_method, status, notes, created_at')
          .neq('status', 'voided')
          .order('created_at', ascending: true);

      final dateStr =
          '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

      // 3. Query settlement overrides up to targetDate (for baseline carry-forward & today's overrides)
      List<dynamic> overridesList = const [];
      try {
        overridesList = await _client
            .from('daily_settlement_overrides')
            .select()
            .lte('settlement_date', dateStr)
            .order('settlement_date', ascending: true);
      } catch (_) {
        // Fallback gracefully if table or permissions are not yet provisioned
      }

      Map<String, dynamic>? todayOverride;
      final priorOverrides = <Map<String, dynamic>>[];

      for (final o in overridesList) {
        if (o is Map<String, dynamic>) {
          final sDate = o['settlement_date']?.toString();
          if (sDate == dateStr) {
            todayOverride = o;
          } else if (sDate != null && sDate.compareTo(dateStr) < 0) {
            priorOverrides.add(o);
          }
        }
      }

      // Find latest prior override baseline (closing override takes precedence over opening override)
      Map<String, dynamic>? latestPrior;
      for (int i = priorOverrides.length - 1; i >= 0; i--) {
        final o = priorOverrides[i];
        final hasOpening = (o['opening_cash'] != null && (o['opening_cash'] as num) > 0) ||
            (o['opening_upi'] != null && (o['opening_upi'] as num) > 0);
        final hasClosing = o['closing_cash'] != null || o['closing_upi'] != null;
        if (hasOpening || hasClosing) {
          latestPrior = o;
          break;
        }
      }

      DateTime? accumulatorStart;
      double openingCash = 0.0;
      double openingUpi = 0.0;
      double openingOther = 0.0;

      if (latestPrior != null) {
        final priorDateStr = latestPrior['settlement_date']?.toString() ?? '';
        final parsedPriorDate = DateTime.tryParse(priorDateStr) ?? targetDate;
        final priorLocalDay = DateTime(parsedPriorDate.year, parsedPriorDate.month, parsedPriorDate.day);

        final hasClosing = latestPrior['closing_cash'] != null || latestPrior['closing_upi'] != null;
        if (hasClosing) {
          openingCash = (latestPrior['closing_cash'] as num?)?.toDouble() ?? 0.0;
          openingUpi = (latestPrior['closing_upi'] as num?)?.toDouble() ?? 0.0;
          accumulatorStart = priorLocalDay.add(const Duration(days: 1));
        } else {
          openingCash = (latestPrior['opening_cash'] as num?)?.toDouble() ?? 0.0;
          openingUpi = (latestPrior['opening_upi'] as num?)?.toDouble() ?? 0.0;
          accumulatorStart = priorLocalDay;
        }
      }

      double salesCash = 0.0;
      double salesUpi = 0.0;
      double salesOther = 0.0;

      double expensesCash = 0.0;
      double expensesUpi = 0.0;
      double expensesOther = 0.0;

      final List<SettlementTransactionItem> dayTransactions = [];

      // Process Payments (Sales)
      for (final p in paymentsResponse) {
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final method = (p['payment_method'] as String? ?? 'cash').toLowerCase();
        final createdAt = DateTime.tryParse(p['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
        final billMap = p['bills'] as Map?;
        final billNum = billMap != null ? billMap['bill_number']?.toString() ?? '' : '';

        if (createdAt.isBefore(startOfDay)) {
          // Contributes to Opening Balance prior to today (since accumulatorStart if established)
          final shouldAccumulate = accumulatorStart == null || !createdAt.isBefore(accumulatorStart);
          if (shouldAccumulate) {
            if (method == 'cash') {
              openingCash += amt;
            } else if (method == 'upi') {
              openingUpi += amt;
            } else {
              openingOther += amt;
            }
          }
        } else if (createdAt.isBefore(endOfDay)) {
          // Contributes to Today's Sales
          if (method == 'cash') {
            salesCash += amt;
          } else if (method == 'upi') {
            salesUpi += amt;
          } else {
            salesOther += amt;
          }

          dayTransactions.add(SettlementTransactionItem(
            id: p['id']?.toString() ?? '',
            timestamp: createdAt,
            type: 'sale',
            description: billNum.isNotEmpty ? 'Sale - Bill #$billNum' : 'Bill Sale',
            paymentMethod: method,
            amount: amt,
            reference: p['transaction_reference']?.toString(),
          ));
        }
      }

      // Process Expenses
      for (final e in expensesResponse) {
        final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
        final method = (e['payment_method'] as String? ?? 'cash').toLowerCase();
        final createdAt = DateTime.tryParse(e['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
        final name = e['expense_name_snapshot']?.toString() ?? 'Expense';

        if (createdAt.isBefore(startOfDay)) {
          // Reduces Opening Balance prior to today (since accumulatorStart if established)
          final shouldAccumulate = accumulatorStart == null || !createdAt.isBefore(accumulatorStart);
          if (shouldAccumulate) {
            if (method == 'cash') {
              openingCash -= amt;
            } else if (method == 'upi') {
              openingUpi -= amt;
            } else {
              openingOther -= amt;
            }
          }
        } else if (createdAt.isBefore(endOfDay)) {
          // Contributes to Today's Expenses
          if (method == 'cash') {
            expensesCash += amt;
          } else if (method == 'upi') {
            expensesUpi += amt;
          } else {
            expensesOther += amt;
          }

          dayTransactions.add(SettlementTransactionItem(
            id: e['id']?.toString() ?? '',
            timestamp: createdAt,
            type: 'expense',
            description: 'Expense - $name',
            paymentMethod: method,
            amount: amt,
            reference: e['notes']?.toString(),
          ));
        }
      }

      // Sort today's transactions chronologically
      dayTransactions.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Extract today's manual overrides if present
      double? manualOpeningCash;
      double? manualOpeningUpi;
      double? manualClosingCash;
      double? manualClosingUpi;
      String? openingReason;
      String? closingReason;
      String? overrideUpdatedBy;
      DateTime? overrideUpdatedAt;

      if (todayOverride != null) {
        manualOpeningCash = (todayOverride['opening_cash'] as num?)?.toDouble();
        manualOpeningUpi = (todayOverride['opening_upi'] as num?)?.toDouble();
        manualClosingCash = (todayOverride['closing_cash'] as num?)?.toDouble();
        manualClosingUpi = (todayOverride['closing_upi'] as num?)?.toDouble();
        openingReason = todayOverride['opening_reason']?.toString();
        closingReason = todayOverride['closing_reason']?.toString();
        overrideUpdatedBy = todayOverride['updated_by']?.toString();
        overrideUpdatedAt = DateTime.tryParse(todayOverride['updated_at']?.toString() ?? '');
      }

      final summary = SettlementDailySummary(
        date: targetDate,
        openingCash: openingCash,
        openingUpi: openingUpi,
        openingOther: openingOther,
        salesCash: salesCash,
        salesUpi: salesUpi,
        salesOther: salesOther,
        expensesCash: expensesCash,
        expensesUpi: expensesUpi,
        expensesOther: expensesOther,
        manualOpeningCash: manualOpeningCash,
        manualOpeningUpi: manualOpeningUpi,
        manualClosingCash: manualClosingCash,
        manualClosingUpi: manualClosingUpi,
        openingReason: openingReason,
        closingReason: closingReason,
        overrideUpdatedBy: overrideUpdatedBy,
        overrideUpdatedAt: overrideUpdatedAt,
      );

      return (summary: summary, transactions: dayTransactions);
    } catch (_) {
      return (
        summary: SettlementDailySummary(date: targetDate),
        transactions: const <SettlementTransactionItem>[],
      );
    }
  }

  /// Save manual settlement override for a given date when calculated amount is zero.
  Future<void> saveSettlementOverride({
    required DateTime targetDate,
    required String overrideType, // 'opening' or 'closing'
    required double cashAmount,
    required double upiAmount,
    required String reason,
  }) async {
    final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final dateStr =
        '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    await _client.rpc('save_daily_settlement_override', params: {
      'p_settlement_date': dateStr,
      'p_override_type': overrideType,
      'p_cash_amount': cashAmount,
      'p_upi_amount': upiAmount,
      'p_reason': reason,
      'p_start_of_day_utc': startOfDay.toUtc().toIso8601String(),
      'p_end_of_day_utc': endOfDay.toUtc().toIso8601String(),
    });
  }

  /// Reset manual settlement override for a given date back to calculated zero.
  Future<void> resetSettlementOverride({
    required DateTime targetDate,
    required String overrideType, // 'opening', 'closing', or 'both'
    required String reason,
  }) async {
    final dateStr =
        '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    await _client.rpc('reset_daily_settlement_override', params: {
      'p_settlement_date': dateStr,
      'p_override_type': overrideType,
      'p_reason': reason,
    });
  }

  /// Fetch Monthly Settlement for a selected month
  Future<List<SettlementMonthlyDay>> fetchMonthlySettlement(DateTime selectedMonth) async {
    try {
      final startOfMonth = DateTime(selectedMonth.year, selectedMonth.month, 1);
      final daysInMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
      final endOfMonth = DateTime(selectedMonth.year, selectedMonth.month, daysInMonth, 23, 59, 59);

      // Fetch all payments in month
      final paymentsResponse = await _client
          .from('payments')
          .select('amount, payment_method, status, created_at')
          .eq('status', 'completed')
          .gte('created_at', startOfMonth.toIso8601String())
          .lte('created_at', endOfMonth.toIso8601String());

      // Fetch all expenses in month
      final expensesResponse = await _client
          .from('expense_transactions')
          .select('amount, payment_method, status, created_at')
          .neq('status', 'voided')
          .gte('created_at', startOfMonth.toIso8601String())
          .lte('created_at', endOfMonth.toIso8601String());

      // Map day number -> day data
      final Map<int, ({
        double salesCash,
        double salesUpi,
        double salesOther,
        double expCash,
        double expUpi,
        double expOther,
      })> dayMap = {};

      for (int i = 1; i <= daysInMonth; i++) {
        dayMap[i] = (salesCash: 0, salesUpi: 0, salesOther: 0, expCash: 0, expUpi: 0, expOther: 0);
      }

      for (final p in paymentsResponse) {
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final method = (p['payment_method'] as String? ?? 'cash').toLowerCase();
        final dt = DateTime.tryParse(p['created_at']?.toString() ?? '')?.toLocal();
        if (dt != null && dt.month == selectedMonth.month && dt.year == selectedMonth.year) {
          final existing = dayMap[dt.day]!;
          dayMap[dt.day] = (
            salesCash: existing.salesCash + (method == 'cash' ? amt : 0),
            salesUpi: existing.salesUpi + (method == 'upi' ? amt : 0),
            salesOther: existing.salesOther + (method != 'cash' && method != 'upi' ? amt : 0),
            expCash: existing.expCash,
            expUpi: existing.expUpi,
            expOther: existing.expOther,
          );
        }
      }

      for (final e in expensesResponse) {
        final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
        final method = (e['payment_method'] as String? ?? 'cash').toLowerCase();
        final dt = DateTime.tryParse(e['created_at']?.toString() ?? '')?.toLocal();
        if (dt != null && dt.month == selectedMonth.month && dt.year == selectedMonth.year) {
          final existing = dayMap[dt.day]!;
          dayMap[dt.day] = (
            salesCash: existing.salesCash,
            salesUpi: existing.salesUpi,
            salesOther: existing.salesOther,
            expCash: existing.expCash + (method == 'cash' ? amt : 0),
            expUpi: existing.expUpi + (method == 'upi' ? amt : 0),
            expOther: existing.expOther + (method != 'cash' && method != 'upi' ? amt : 0),
          );
        }
      }

      final List<SettlementMonthlyDay> result = [];
      for (int d = 1; d <= daysInMonth; d++) {
        final data = dayMap[d]!;
        final dayDate = DateTime(selectedMonth.year, selectedMonth.month, d);
        result.add(SettlementMonthlyDay(
          date: dayDate,
          salesCash: data.salesCash,
          salesUpi: data.salesUpi,
          salesOther: data.salesOther,
          expensesCash: data.expCash,
          expensesUpi: data.expUpi,
          expensesOther: data.expOther,
        ));
      }

      return result;
    } catch (_) {
      return [];
    }
  }
}
