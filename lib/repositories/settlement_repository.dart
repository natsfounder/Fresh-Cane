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

      double openingCash = 0.0;
      double openingUpi = 0.0;
      double openingOther = 0.0;

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
          // Contributes to Opening Balance prior to today
          if (method == 'cash') {
            openingCash += amt;
          } else if (method == 'upi') {
            openingUpi += amt;
          } else {
            openingOther += amt;
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
          // Reduces Opening Balance prior to today
          if (method == 'cash') {
            openingCash -= amt;
          } else if (method == 'upi') {
            openingUpi -= amt;
          } else {
            openingOther -= amt;
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
      );

      return (summary: summary, transactions: dayTransactions);
    } catch (_) {
      return (
        summary: SettlementDailySummary(date: targetDate),
        transactions: const <SettlementTransactionItem>[],
      );
    }
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
        // Show all days that have any activity, or up to today if in current month
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
