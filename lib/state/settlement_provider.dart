import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settlement_model.dart';
import '../repositories/settlement_repository.dart';

final settlementRepositoryProvider = Provider<SettlementRepository>((ref) {
  return SettlementRepository();
});

class SettlementState {
  final DateTime selectedDate;
  final DateTime selectedMonth;
  final String viewMode; // 'daily' or 'monthly'
  final bool isLoading;
  final SettlementDailySummary? dailySummary;
  final List<SettlementTransactionItem> dailyTransactions;
  final List<SettlementMonthlyDay> monthlyDays;
  final String? errorMessage;

  const SettlementState({
    required this.selectedDate,
    required this.selectedMonth,
    this.viewMode = 'daily',
    this.isLoading = false,
    this.dailySummary,
    this.dailyTransactions = const [],
    this.monthlyDays = const [],
    this.errorMessage,
  });

  SettlementState copyWith({
    DateTime? selectedDate,
    DateTime? selectedMonth,
    String? viewMode,
    bool? isLoading,
    SettlementDailySummary? dailySummary,
    List<SettlementTransactionItem>? dailyTransactions,
    List<SettlementMonthlyDay>? monthlyDays,
    String? errorMessage,
  }) {
    return SettlementState(
      selectedDate: selectedDate ?? this.selectedDate,
      selectedMonth: selectedMonth ?? this.selectedMonth,
      viewMode: viewMode ?? this.viewMode,
      isLoading: isLoading ?? this.isLoading,
      dailySummary: dailySummary ?? this.dailySummary,
      dailyTransactions: dailyTransactions ?? this.dailyTransactions,
      monthlyDays: monthlyDays ?? this.monthlyDays,
      errorMessage: errorMessage,
    );
  }

  // Monthly Aggregates
  double get grossMonthlyCashSales => monthlyDays.fold(0.0, (s, d) => s + d.salesCash);
  double get grossMonthlyUpiSales => monthlyDays.fold(0.0, (s, d) => s + d.salesUpi);
  double get grossMonthlyTotalSales => monthlyDays.fold(0.0, (s, d) => s + d.salesTotal);

  double get grossMonthlyCashExpenses => monthlyDays.fold(0.0, (s, d) => s + d.expensesCash);
  double get grossMonthlyUpiExpenses => monthlyDays.fold(0.0, (s, d) => s + d.expensesUpi);
  double get grossMonthlyTotalExpenses => monthlyDays.fold(0.0, (s, d) => s + d.expensesTotal);

  double get grossMonthlyCashNet => grossMonthlyCashSales - grossMonthlyCashExpenses;
  double get grossMonthlyUpiNet => grossMonthlyUpiSales - grossMonthlyUpiExpenses;
  double get grossMonthlyTotalNet => grossMonthlyTotalSales - grossMonthlyTotalExpenses;
}

final settlementProvider =
    NotifierProvider<SettlementNotifier, SettlementState>(() {
  return SettlementNotifier();
});

class SettlementNotifier extends Notifier<SettlementState> {
  SettlementRepository get _repo => ref.read(settlementRepositoryProvider);

  @override
  SettlementState build() {
    final now = DateTime.now();
    final initialState = SettlementState(
      selectedDate: DateTime(now.year, now.month, now.day),
      selectedMonth: DateTime(now.year, now.month, 1),
      dailySummary: SettlementDailySummary(date: now),
    );
    Future.microtask(() => loadSettlementData());
    return initialState;
  }

  void setViewMode(String mode) {
    if (state.viewMode != mode) {
      state = state.copyWith(viewMode: mode);
      loadSettlementData();
    }
  }

  void setDate(DateTime date) {
    state = state.copyWith(selectedDate: date);
    loadDailySettlement(date);
  }

  void setMonth(DateTime month) {
    state = state.copyWith(selectedMonth: month);
    loadMonthlySettlement(month);
  }

  Future<void> loadSettlementData() async {
    if (state.viewMode == 'daily') {
      await loadDailySettlement(state.selectedDate);
    } else {
      await loadMonthlySettlement(state.selectedMonth);
    }
  }

  Future<void> loadDailySettlement(DateTime date) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _repo.fetchDailySettlement(date);
      state = state.copyWith(
        isLoading: false,
        dailySummary: res.summary,
        dailyTransactions: res.transactions,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> loadMonthlySettlement(DateTime month) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final days = await _repo.fetchMonthlySettlement(month);
      state = state.copyWith(
        isLoading: false,
        monthlyDays: days,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}
