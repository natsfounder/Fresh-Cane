import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense_model.dart';
import '../repositories/expense_repository.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository();
});

class CashierExpenseState {
  final bool isLoading;
  final bool isSubmitting;
  final DateTime targetDate;
  final String targetPeriod;
  final String monthLabel;
  final double totalExpenses;
  final double fixedTotal;
  final double nonFixedTotal;
  final int fixedCount;
  final int nonFixedCount;
  final List<ExpenseTransaction> expenses;
  final List<ExpenseDefinition> fixedDefinitions;
  final String? errorMessage;
  final String? successMessage;

  const CashierExpenseState({
    this.isLoading = false,
    this.isSubmitting = false,
    required this.targetDate,
    this.targetPeriod = '',
    this.monthLabel = '',
    this.totalExpenses = 0.0,
    this.fixedTotal = 0.0,
    this.nonFixedTotal = 0.0,
    this.fixedCount = 0,
    this.nonFixedCount = 0,
    this.expenses = const [],
    this.fixedDefinitions = const [],
    this.errorMessage,
    this.successMessage,
  });

  factory CashierExpenseState.initial() {
    final now = DateTime.now();
    final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return CashierExpenseState(
      targetDate: now,
      targetPeriod: period,
    );
  }

  CashierExpenseState copyWith({
    bool? isLoading,
    bool? isSubmitting,
    DateTime? targetDate,
    String? targetPeriod,
    String? monthLabel,
    double? totalExpenses,
    double? fixedTotal,
    double? nonFixedTotal,
    int? fixedCount,
    int? nonFixedCount,
    List<ExpenseTransaction>? expenses,
    List<ExpenseDefinition>? fixedDefinitions,
    String? errorMessage,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return CashierExpenseState(
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      targetDate: targetDate ?? this.targetDate,
      targetPeriod: targetPeriod ?? this.targetPeriod,
      monthLabel: monthLabel ?? this.monthLabel,
      totalExpenses: totalExpenses ?? this.totalExpenses,
      fixedTotal: fixedTotal ?? this.fixedTotal,
      nonFixedTotal: nonFixedTotal ?? this.nonFixedTotal,
      fixedCount: fixedCount ?? this.fixedCount,
      nonFixedCount: nonFixedCount ?? this.nonFixedCount,
      expenses: expenses ?? this.expenses,
      fixedDefinitions: fixedDefinitions ?? this.fixedDefinitions,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

final cashierExpenseProvider =
    NotifierProvider<CashierExpenseNotifier, CashierExpenseState>(() {
  return CashierExpenseNotifier();
});

class CashierExpenseNotifier extends Notifier<CashierExpenseState> {
  ExpenseRepository get _repository => ref.read(expenseRepositoryProvider);

  @override
  CashierExpenseState build() {
    Future.microtask(() => loadExpenses());
    return CashierExpenseState.initial();
  }

  Future<void> loadExpenses({DateTime? targetDate}) async {
    final date = targetDate ?? state.targetDate;
    state = state.copyWith(isLoading: true, targetDate: date, clearError: true);
    try {
      final res = await _repository.fetchCashierMonthExpenses(targetDate: date);

      state = state.copyWith(
        isLoading: false,
        targetPeriod: res.targetPeriod,
        monthLabel: res.monthLabel,
        totalExpenses: res.totalExpenses,
        fixedTotal: res.fixedTotal,
        nonFixedTotal: res.nonFixedTotal,
        fixedCount: res.fixedCount,
        nonFixedCount: res.nonFixedCount,
        expenses: res.expenses,
        fixedDefinitions: res.fixedDefinitions,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load expenses: $e',
      );
    }
  }

  /// Records a Fixed Expense where the name was defined by Admin and cashier enters amount or sub-expenses.
  Future<bool> submitFixedExpense({
    required String definitionId,
    required double amount,
    required String paymentMethod,
    String? notes,
    List<SubExpenseItem>? subExpenses,
    String? applicablePeriod,
    DateTime? expenseDate,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true, clearSuccess: true);
    try {
      await _repository.recordExpenseTransaction(
        definitionId: definitionId,
        amount: amount,
        paymentMethod: paymentMethod,
        notes: notes,
        subExpenses: subExpenses,
        applicablePeriod: applicablePeriod,
        expenseDate: expenseDate,
      );

      state = state.copyWith(
        isSubmitting: false,
        successMessage: 'Expense recorded successfully!',
      );

      await loadExpenses(targetDate: state.targetDate);
      return true;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.toString().replaceAll('Exception: ', '').replaceAll('RepositoryFailureException: ', ''),
      );
      return false;
    }
  }

  /// Records a Non-Fixed Expense where cashier creates a custom name and optional sub-expenses.
  Future<bool> submitNonFixedExpense({
    required String customName,
    required double amount,
    required String paymentMethod,
    String? notes,
    List<SubExpenseItem>? subExpenses,
    DateTime? expenseDate,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true, clearSuccess: true);
    try {
      await _repository.recordExpenseTransaction(
        customName: customName,
        amount: amount,
        paymentMethod: paymentMethod,
        notes: notes,
        subExpenses: subExpenses,
        expenseDate: expenseDate,
      );

      state = state.copyWith(
        isSubmitting: false,
        successMessage: 'Expense recorded successfully!',
      );

      await loadExpenses(targetDate: state.targetDate);
      return true;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.toString().replaceAll('Exception: ', '').replaceAll('RepositoryFailureException: ', ''),
      );
      return false;
    }
  }

  /// Edits an existing expense transaction and audits the change with timestamp.
  Future<bool> editExpense({
    required String transactionId,
    required double amount,
    required String paymentMethod,
    String? notes,
    List<SubExpenseItem>? subExpenses,
    String? editReason,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true, clearSuccess: true);
    try {
      await _repository.editExpenseTransaction(
        transactionId: transactionId,
        amount: amount,
        paymentMethod: paymentMethod,
        notes: notes,
        subExpenses: subExpenses,
        editReason: editReason,
      );

      state = state.copyWith(
        isSubmitting: false,
        successMessage: 'Expense updated successfully!',
      );

      await loadExpenses(targetDate: state.targetDate);
      return true;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.toString().replaceAll('Exception: ', '').replaceAll('RepositoryFailureException: ', ''),
      );
      return false;
    }
  }

  /// Soft deletes an expense transaction.
  Future<bool> deleteExpense({
    required String transactionId,
    String? deleteReason,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true, clearSuccess: true);
    try {
      await _repository.deleteExpenseTransaction(
        transactionId: transactionId,
        deleteReason: deleteReason,
      );

      state = state.copyWith(
        isSubmitting: false,
        successMessage: 'Expense deleted successfully!',
      );

      await loadExpenses(targetDate: state.targetDate);
      return true;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.toString().replaceAll('Exception: ', '').replaceAll('RepositoryFailureException: ', ''),
      );
      return false;
    }
  }

  void clearNotifications() {
    state = state.copyWith(clearError: true, clearSuccess: true);
  }
}
