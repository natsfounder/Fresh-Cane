import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Represents an itemized sub-expense under a parent expense (e.g. Apple: ₹50 under Fruit).
@immutable
class SubExpenseItem {
  final String name;
  final double amount;

  const SubExpenseItem({
    required this.name,
    required this.amount,
  });

  SubExpenseItem copyWith({
    String? name,
    double? amount,
  }) {
    return SubExpenseItem(
      name: name ?? this.name,
      amount: amount ?? this.amount,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'amount': amount,
  };

  factory SubExpenseItem.fromJson(Map<String, dynamic> json) {
    return SubExpenseItem(
      name: (json['name'] ?? json['item_name'] ?? json['title'] ?? '').toString().trim(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubExpenseItem &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          amount == other.amount;

  @override
  int get hashCode => name.hashCode ^ amount.hashCode;
}

/// Representation of an Admin-configured Expense Definition / Template.
@immutable
class ExpenseDefinition {
  final String id;
  final String name;
  final String? description;
  final String expenseType; // 'mandatory' | 'occasional'
  final String frequency; // 'monthly' | 'every_2_months' | 'every_3_months' | 'every_6_months' | 'yearly' | 'as_needed'
  final DateTime startDate;
  final bool isActive;
  final DateTime createdAt;
  final List<String> defaultSubExpenses;

  const ExpenseDefinition({
    required this.id,
    required this.name,
    this.description,
    required this.expenseType,
    required this.frequency,
    required this.startDate,
    required this.isActive,
    required this.createdAt,
    this.defaultSubExpenses = const [],
  });

  bool get isMandatory => expenseType == 'mandatory';
  bool get isOccasional => expenseType == 'occasional';
  bool get hasSubExpenses => defaultSubExpenses.isNotEmpty;

  String get displayDescription {
    if (description == null || description!.isEmpty) return '';
    return description!.replaceAll(RegExp(r'<!--sub_expenses:.*?-->', dotAll: true), '').trim();
  }

  String get frequencyLabel {
    switch (frequency) {
      case 'monthly':
        return 'Monthly';
      case 'every_2_months':
        return 'Every 2 Months';
      case 'every_3_months':
        return 'Every 3 Months';
      case 'every_6_months':
        return 'Every 6 Months';
      case 'yearly':
        return 'Yearly';
      case 'as_needed':
        return 'As Needed';
      default:
        return frequency;
    }
  }

  static String? buildDescriptionWithSubExpenses(String? baseDesc, List<String>? subExpenses) {
    final clean = (baseDesc ?? '').replaceAll(RegExp(r'<!--sub_expenses:.*?-->', dotAll: true), '').trim();
    if (subExpenses == null || subExpenses.isEmpty) {
      return clean.isEmpty ? null : clean;
    }
    final cleanItems = subExpenses.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (cleanItems.isEmpty) return clean.isEmpty ? null : clean;
    final tag = '<!--sub_expenses:${jsonEncode(cleanItems)}-->';
    return clean.isEmpty ? tag : '$clean\n$tag';
  }

  factory ExpenseDefinition.fromJson(Map<String, dynamic> json) {
    List<String> parsedSubExpenses = [];
    if (json['sub_expenses'] is List) {
      parsedSubExpenses = (json['sub_expenses'] as List)
          .map((e) => e is Map ? (e['name'] ?? '').toString() : e.toString())
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (json['default_sub_expenses'] is List) {
      parsedSubExpenses = (json['default_sub_expenses'] as List)
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (json['description'] != null) {
      final raw = json['description'].toString();
      final match = RegExp(r'<!--sub_expenses:(.*?)-->', dotAll: true).firstMatch(raw);
      if (match != null) {
        try {
          final decoded = jsonDecode(match.group(1)!);
          if (decoded is List) {
            parsedSubExpenses = decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          }
        } catch (_) {}
      }
    }

    return ExpenseDefinition(
      id: (json['id'] ?? json['definition_id'] ?? '').toString(),
      name: (json['name'] ?? 'Expense').toString(),
      description: json['description'] as String?,
      expenseType: json['expense_type'] as String? ?? 'mandatory',
      frequency: json['frequency'] as String? ?? 'monthly',
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      defaultSubExpenses: parsedSubExpenses,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'expense_type': expenseType,
      'frequency': frequency,
      'start_date': startDate.toIso8601String().substring(0, 10),
      'is_active': isActive,
      'sub_expenses': defaultSubExpenses,
    };
  }
}

/// Representation of an actual Cashier-recorded Expense Financial Transaction.
@immutable
class ExpenseTransaction {
  final String id;
  final String? definitionId;
  final String expenseName;
  final bool isFixed;
  final String expenseType;
  final String frequency;
  final String? applicablePeriod;
  final DateTime expenseDate;
  final double amount;
  final double? originalAmount;
  final String paymentMethod;
  final String? notes;
  final String status;
  final String? recordedById;
  final String recordedByName;
  final bool isEdited;
  final DateTime? editedAt;
  final String? editedByName;
  final String? editReason;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedByName;
  final String? deleteReason;
  final DateTime createdAt;
  final List<SubExpenseItem> subExpenses;

  const ExpenseTransaction({
    required this.id,
    this.definitionId,
    required this.expenseName,
    this.isFixed = true,
    required this.expenseType,
    required this.frequency,
    this.applicablePeriod,
    required this.expenseDate,
    required this.amount,
    this.originalAmount,
    required this.paymentMethod,
    this.notes,
    required this.status,
    this.recordedById,
    required this.recordedByName,
    this.isEdited = false,
    this.editedAt,
    this.editedByName,
    this.editReason,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedByName,
    this.deleteReason,
    required this.createdAt,
    this.subExpenses = const [],
  });

  bool get isMandatory => expenseType == 'mandatory';
  bool get hasSubExpenses => subExpenses.isNotEmpty;

  String get subExpensesSummary =>
      subExpenses.map((s) => '${s.name}: ₹${s.amount.toStringAsFixed(2)}').join(', ');

  String get displayNotes {
    if (notes == null || notes!.isEmpty) return '';
    return notes!.replaceAll(RegExp(r'<!--sub_expenses:.*?-->', dotAll: true), '').trim();
  }

  String get paymentMethodLabel {
    switch (paymentMethod.toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'upi':
        return 'UPI';
      case 'bank_transfer':
        return 'Bank Transfer';
      case 'card':
        return 'Card';
      default:
        return paymentMethod.toUpperCase();
    }
  }

  static String? buildNotesWithSubExpenses(String? baseNotes, List<SubExpenseItem>? subExpenses) {
    final clean = (baseNotes ?? '').replaceAll(RegExp(r'<!--sub_expenses:.*?-->', dotAll: true), '').trim();
    if (subExpenses == null || subExpenses.isEmpty) {
      return clean.isEmpty ? null : clean;
    }
    final itemsList = subExpenses.where((s) => s.name.trim().isNotEmpty).toList();
    if (itemsList.isEmpty) return clean.isEmpty ? null : clean;

    final jsonTag = '<!--sub_expenses:${jsonEncode(itemsList.map((e) => e.toJson()).toList())}-->';
    final breakdown = 'Items: ${itemsList.map((e) => '${e.name}: ₹${e.amount.toStringAsFixed(2)}').join(', ')}';
    final userNote = clean.isNotEmpty ? '\nNote: $clean' : '';
    return '$breakdown$userNote\n$jsonTag';
  }

  factory ExpenseTransaction.fromJson(Map<String, dynamic> json) {
    List<SubExpenseItem> parsedItems = [];
    if (json['sub_expenses'] is List) {
      parsedItems = (json['sub_expenses'] as List)
          .whereType<Map>()
          .map((m) => SubExpenseItem.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } else if (json['notes'] != null) {
      final rawNotes = json['notes'].toString();
      final match = RegExp(r'<!--sub_expenses:(.*?)-->', dotAll: true).firstMatch(rawNotes);
      if (match != null) {
        try {
          final decoded = jsonDecode(match.group(1)!);
          if (decoded is List) {
            parsedItems = decoded
                .whereType<Map>()
                .map((m) => SubExpenseItem.fromJson(Map<String, dynamic>.from(m)))
                .toList();
          }
        } catch (_) {}
      }
    }

    return ExpenseTransaction(
      id: json['id'] as String,
      definitionId: json['definition_id'] as String?,
      expenseName: (json['expense_name'] ?? json['name'] ?? 'Expense').toString(),
      isFixed: json['is_fixed'] as bool? ?? (json['definition_id'] != null),
      expenseType: json['expense_type'] as String? ?? 'mandatory',
      frequency: json['frequency'] as String? ?? 'monthly',
      applicablePeriod: json['applicable_period'] as String?,
      expenseDate: json['expense_date'] != null
          ? DateTime.tryParse(json['expense_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      originalAmount: (json['original_amount'] as num?)?.toDouble(),
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'completed',
      recordedById: json['recorded_by_id'] as String?,
      recordedByName: json['recorded_by_name'] as String? ?? 'Staff',
      isEdited: json['is_edited'] as bool? ?? false,
      editedAt: json['edited_at'] != null ? DateTime.tryParse(json['edited_at'].toString())?.toLocal() : null,
      editedByName: json['edited_by_name'] as String?,
      editReason: json['edit_reason'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? (json['status'] == 'deleted'),
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'].toString())?.toLocal() : null,
      deletedByName: json['deleted_by_name'] as String?,
      deleteReason: json['delete_reason'] as String?,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString())?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      subExpenses: parsedItems,
    );
  }
}

/// Helper model for Cashier Monthly View Data
@immutable
class CashierMonthExpenseData {
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

  const CashierMonthExpenseData({
    required this.targetDate,
    required this.targetPeriod,
    required this.monthLabel,
    required this.totalExpenses,
    required this.fixedTotal,
    required this.nonFixedTotal,
    required this.fixedCount,
    required this.nonFixedCount,
    required this.expenses,
    required this.fixedDefinitions,
  });

  factory CashierMonthExpenseData.empty(DateTime date) {
    final period = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    return CashierMonthExpenseData(
      targetDate: date,
      targetPeriod: period,
      monthLabel: '',
      totalExpenses: 0.0,
      fixedTotal: 0.0,
      nonFixedTotal: 0.0,
      fixedCount: 0,
      nonFixedCount: 0,
      expenses: const [],
      fixedDefinitions: const [],
    );
  }

  factory CashierMonthExpenseData.fromJson(Map<String, dynamic> json) {
    final rawExpenses = json['expenses'] as List? ?? [];
    final rawDefs = json['fixed_definitions'] as List? ?? [];

    return CashierMonthExpenseData(
      targetDate: json['target_date'] != null
          ? DateTime.tryParse(json['target_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      targetPeriod: (json['target_period'] ?? '').toString(),
      monthLabel: (json['month_label'] ?? '').toString(),
      totalExpenses: (json['total_expenses'] as num?)?.toDouble() ?? 0.0,
      fixedTotal: (json['fixed_total'] as num?)?.toDouble() ?? 0.0,
      nonFixedTotal: (json['non_fixed_total'] as num?)?.toDouble() ?? 0.0,
      fixedCount: (json['fixed_count'] as num?)?.toInt() ?? 0,
      nonFixedCount: (json['non_fixed_count'] as num?)?.toInt() ?? 0,
      expenses: rawExpenses
          .map((e) => ExpenseTransaction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      fixedDefinitions: rawDefs
          .map((d) => ExpenseDefinition.fromJson(Map<String, dynamic>.from(d as Map)))
          .toList(),
    );
  }
}

/// Helper model for Cashier applicable expense display
@immutable
class CashierApplicableExpense {
  final String definitionId;
  final String name;
  final String? description;
  final String expenseType;
  final String frequency;
  final DateTime startDate;
  final String? applicablePeriod;
  final bool isRecorded;
  final String? transactionId;
  final double? recordedAmount;
  final String? paymentMethod;
  final String? notes;
  final DateTime? expenseDate;
  final String? recordedByName;
  final DateTime? recordedAt;

  const CashierApplicableExpense({
    required this.definitionId,
    required this.name,
    this.description,
    required this.expenseType,
    required this.frequency,
    required this.startDate,
    this.applicablePeriod,
    required this.isRecorded,
    this.transactionId,
    this.recordedAmount,
    this.paymentMethod,
    this.notes,
    this.expenseDate,
    this.recordedByName,
    this.recordedAt,
  });

  bool get isMandatory => expenseType == 'mandatory';

  String get frequencyLabel {
    switch (frequency) {
      case 'monthly':
        return 'Monthly';
      case 'every_2_months':
        return 'Every 2 Months';
      case 'every_3_months':
        return 'Every 3 Months';
      case 'every_6_months':
        return 'Every 6 Months';
      case 'yearly':
        return 'Yearly';
      case 'as_needed':
        return 'As Needed';
      default:
        return frequency;
    }
  }

  factory CashierApplicableExpense.fromJson(Map<String, dynamic> json) {
    return CashierApplicableExpense(
      definitionId: (json['definition_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Expense').toString(),
      description: json['description'] as String?,
      expenseType: json['expense_type'] as String? ?? 'mandatory',
      frequency: json['frequency'] as String? ?? 'monthly',
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'].toString())
          : DateTime.now(),
      applicablePeriod: json['applicable_period'] as String?,
      isRecorded: json['is_recorded'] as bool? ?? false,
      transactionId: json['transaction_id'] as String?,
      recordedAmount: (json['recorded_amount'] as num?)?.toDouble(),
      paymentMethod: json['payment_method'] as String?,
      notes: json['notes'] as String?,
      expenseDate: json['expense_date'] != null
          ? DateTime.parse(json['expense_date'].toString())
          : null,
      recordedByName: json['recorded_by_name'] as String?,
      recordedAt: json['recorded_at'] != null
          ? DateTime.parse(json['recorded_at'].toString())
          : null,
    );
  }
}
