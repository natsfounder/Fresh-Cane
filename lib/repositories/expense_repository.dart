import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/domain_exceptions.dart';
import '../models/expense_model.dart';
import '../services/supabase_service.dart';

/// Repository managing Expense Definitions, Cashier Transactions, and Reports.
class ExpenseRepository {
  final SupabaseClient _client;

  ExpenseRepository([SupabaseClient? client])
      : _client = client ?? SupabaseService.client;

  FreshCaneException _handleError(dynamic error) {
    if (error is PostgrestException) {
      debugPrint('[ExpenseRepository] PostgrestException: ${error.message} (${error.code})');
      return RepositoryFailureException(error.message, error);
    }
    return RepositoryFailureException(error.toString(), error);
  }

  // ---------------------------------------------------------------------------
  // CASHIER EXPENSE OPERATIONS
  // ---------------------------------------------------------------------------

  /// Fetches current month's expenses and available fixed definitions strictly for Cashier.
  Future<CashierMonthExpenseData> fetchCashierMonthExpenses({DateTime? targetDate}) async {
    try {
      final date = targetDate ?? DateTime.now();
      final dateStr = date.toIso8601String().substring(0, 10);
      final response = await _client.rpc(
        'get_cashier_month_expenses',
        params: {'p_target_date': dateStr},
      );

      final data = Map<String, dynamic>.from(response as Map);
      return CashierMonthExpenseData.fromJson(data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Fetches applicable mandatory expenses and available occasional definitions for Cashier (legacy compatibility).
  Future<Map<String, dynamic>> fetchApplicableExpenses({DateTime? targetDate}) async {
    try {
      final dateStr = (targetDate ?? DateTime.now()).toIso8601String().substring(0, 10);
      final response = await _client.rpc(
        'get_cashier_applicable_expenses',
        params: {'p_target_date': dateStr},
      );

      final data = Map<String, dynamic>.from(response as Map);
      final rawMandatory = (data['mandatory_expenses'] as List? ?? []);
      final rawOccasional = (data['occasional_definitions'] as List? ?? []);

      final mandatory = rawMandatory
          .map((m) => CashierApplicableExpense.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList();

      final occasional = rawOccasional
          .map((o) => ExpenseDefinition.fromJson(Map<String, dynamic>.from(o as Map)))
          .toList();

      return {
        'target_date': data['target_date'],
        'target_period': data['target_period'],
        'mandatory_expenses': mandatory,
        'occasional_definitions': occasional,
      };
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Records an actual expense financial transaction (Fixed or Non-Fixed).
  Future<Map<String, dynamic>> recordExpenseTransaction({
    String? definitionId,
    String? customName,
    required double amount,
    required String paymentMethod,
    String? notes,
    List<SubExpenseItem>? subExpenses,
    String? applicablePeriod,
    DateTime? expenseDate,
  }) async {
    try {
      final dateStr = (expenseDate ?? DateTime.now()).toIso8601String().substring(0, 10);
      final finalNotes = ExpenseTransaction.buildNotesWithSubExpenses(notes, subExpenses);
      final response = await _client.rpc(
        'record_expense_transaction',
        params: {
          'p_definition_id': definitionId,
          'p_custom_name': customName,
          'p_amount': amount,
          'p_payment_method': paymentMethod,
          'p_notes': finalNotes,
          'p_applicable_period': applicablePeriod,
          'p_expense_date': dateStr,
          'p_sub_expenses': subExpenses != null ? subExpenses.map((s) => s.toJson()).toList() : [],
        },
      );

      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Edits an existing expense transaction and records an audit log.
  Future<Map<String, dynamic>> editExpenseTransaction({
    required String transactionId,
    required double amount,
    required String paymentMethod,
    String? notes,
    List<SubExpenseItem>? subExpenses,
    String? editReason,
  }) async {
    try {
      final finalNotes = ExpenseTransaction.buildNotesWithSubExpenses(notes, subExpenses);
      final response = await _client.rpc(
        'edit_expense_transaction',
        params: {
          'p_transaction_id': transactionId,
          'p_amount': amount,
          'p_payment_method': paymentMethod,
          'p_notes': finalNotes,
          'p_edit_reason': editReason,
          'p_sub_expenses': subExpenses?.map((s) => s.toJson()).toList(),
        },
      );

      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Soft deletes an existing expense transaction with optional reason.
  Future<Map<String, dynamic>> deleteExpenseTransaction({
    required String transactionId,
    String? deleteReason,
  }) async {
    try {
      final response = await _client.rpc(
        'delete_expense_transaction',
        params: {
          'p_transaction_id': transactionId,
          'p_delete_reason': deleteReason,
        },
      );

      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // ADMIN EXPENSE DEFINITIONS (MANAGEMENT)
  // ---------------------------------------------------------------------------

  /// Fetches all expense definitions (mandatory & occasional, active & inactive).
  Future<List<ExpenseDefinition>> fetchExpenseDefinitions() async {
    try {
      final response = await _client
          .from('expense_definitions')
          .select('*')
          .order('expense_type', ascending: false) // mandatory first
          .order('name', ascending: true);

      final list = response as List;
      return list
          .map((d) => ExpenseDefinition.fromJson(Map<String, dynamic>.from(d as Map)))
          .toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Creates a new expense definition.
  Future<ExpenseDefinition> createExpenseDefinition({
    required String name,
    String? description,
    required String expenseType,
    required String frequency,
    required DateTime startDate,
    bool isActive = true,
    List<String>? subExpenses,
  }) async {
    try {
      final callerId = _client.auth.currentUser?.id;
      final encodedDesc = ExpenseDefinition.buildDescriptionWithSubExpenses(description, subExpenses);
      final payload = {
        'name': name.trim(),
        'description': encodedDesc?.trim(),
        'expense_type': expenseType,
        'frequency': frequency,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'is_active': isActive,
        'sub_expenses': subExpenses ?? [],
        'created_by': callerId,
      };

      final response = await _client
          .from('expense_definitions')
          .insert(payload)
          .select('*')
          .single();

      return ExpenseDefinition.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Updates an existing expense definition.
  Future<ExpenseDefinition> updateExpenseDefinition({
    required String id,
    required String name,
    String? description,
    required String expenseType,
    required String frequency,
    required DateTime startDate,
    required bool isActive,
    List<String>? subExpenses,
  }) async {
    try {
      final callerId = _client.auth.currentUser?.id;
      final encodedDesc = ExpenseDefinition.buildDescriptionWithSubExpenses(description, subExpenses);
      final payload = {
        'name': name.trim(),
        'description': encodedDesc?.trim(),
        'expense_type': expenseType,
        'frequency': frequency,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'is_active': isActive,
        'sub_expenses': subExpenses ?? [],
        'updated_by': callerId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _client
          .from('expense_definitions')
          .update(payload)
          .eq('id', id)
          .select('*')
          .single();

      return ExpenseDefinition.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Toggles active status of an expense definition.
  Future<void> toggleExpenseDefinitionActive(String id, bool isActive) async {
    try {
      final callerId = _client.auth.currentUser?.id;
      await _client.from('expense_definitions').update({
        'is_active': isActive,
        'updated_by': callerId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // ADMIN EXPENSE REPORTING
  // ---------------------------------------------------------------------------

  /// Fetches executive expense report data with summary and transaction records.
  Future<Map<String, dynamic>> fetchExpenseReport({
    required DateTime startDate,
    required DateTime endDate,
    String? definitionId,
    String? expenseType,
    String? paymentMethod,
    String? recordedBy,
    String filterStatus = 'all', // 'all', 'active_only', 'deleted_only'
  }) async {
    try {
      final startStr = startDate.toIso8601String().substring(0, 10);
      final endStr = endDate.toIso8601String().substring(0, 10);

      final response = await _client.rpc(
        'get_admin_expense_report',
        params: {
          'p_start_date': startStr,
          'p_end_date': endStr,
          'p_filter_status': filterStatus,
          if (definitionId != null && definitionId.isNotEmpty) 'p_definition_id': definitionId,
          if (expenseType != null && expenseType.isNotEmpty) 'p_expense_type': expenseType,
          if (paymentMethod != null && paymentMethod.isNotEmpty) 'p_payment_method': paymentMethod,
          if (recordedBy != null && recordedBy.isNotEmpty) 'p_recorded_by': recordedBy,
        },
      );

      final data = Map<String, dynamic>.from(response as Map);
      final rawRecords = (data['transactions'] ?? data['records'] as List? ?? []) as List;
      final transactions = rawRecords
          .map((r) => ExpenseTransaction.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();

      return {
        'start_date': data['start_date'] ?? startStr,
        'end_date': data['end_date'] ?? endStr,
        'summary': Map<String, dynamic>.from(data['summary'] as Map? ?? {}),
        'records_count': transactions.length,
        'transactions': transactions,
      };
    } catch (e) {
      throw _handleError(e);
    }
  }
}
