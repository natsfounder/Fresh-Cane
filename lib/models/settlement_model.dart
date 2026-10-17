/// Settlement Data Models for Fresh Cane POS
/// Supports Daily and Monthly payment-position settlement:
/// Opening Balance + Sales − Expenses = Closing Balance (Calculated independently per payment method)
class SettlementDailySummary {
  final DateTime date;
  // Automatically calculated ledger movements
  final double openingCash;
  final double openingUpi;
  final double openingOther;
  final double salesCash;
  final double salesUpi;
  final double salesOther;
  final double expensesCash;
  final double expensesUpi;
  final double expensesOther;

  // Controlled manual override fields (null when no manual override exists)
  final double? manualOpeningCash;
  final double? manualOpeningUpi;
  final double? manualClosingCash;
  final double? manualClosingUpi;
  final String? openingReason;
  final String? closingReason;
  final String? overrideUpdatedBy;
  final DateTime? overrideUpdatedAt;

  const SettlementDailySummary({
    required this.date,
    this.openingCash = 0.0,
    this.openingUpi = 0.0,
    this.openingOther = 0.0,
    this.salesCash = 0.0,
    this.salesUpi = 0.0,
    this.salesOther = 0.0,
    this.expensesCash = 0.0,
    this.expensesUpi = 0.0,
    this.expensesOther = 0.0,
    this.manualOpeningCash,
    this.manualOpeningUpi,
    this.manualClosingCash,
    this.manualClosingUpi,
    this.openingReason,
    this.closingReason,
    this.overrideUpdatedBy,
    this.overrideUpdatedAt,
  });

  // --- RAW AUTOMATIC LEDGER VALUES ---
  double get openingTotal => openingCash + openingUpi + openingOther;
  double get salesTotal => salesCash + salesUpi + salesOther;
  double get expensesTotal => expensesCash + expensesUpi + expensesOther;

  double get closingCash => openingCash + salesCash - expensesCash;
  double get closingUpi => openingUpi + salesUpi - expensesUpi;
  double get closingOther => openingOther + salesOther - expensesOther;
  double get closingTotal => openingTotal + salesTotal - expensesTotal;

  double get netCash => salesCash - expensesCash;
  double get netUpi => salesUpi - expensesUpi;
  double get netOther => salesOther - expensesOther;
  double get netTotal => salesTotal - expensesTotal;

  // --- MANUAL ADJUSTMENT STATE ---
  bool get hasManualOpening =>
      manualOpeningCash != null || manualOpeningUpi != null;

  bool get hasManualClosing =>
      manualClosingCash != null || manualClosingUpi != null;

  double get manualOpeningTotal =>
      (manualOpeningCash ?? 0.0) + (manualOpeningUpi ?? 0.0);

  double get manualClosingTotal =>
      (manualClosingCash ?? 0.0) + (manualClosingUpi ?? 0.0);

  /// Eligibility: Manual entry is STRICTLY permitted only when the natural calculated amount is exactly 0.
  bool get canEnterManualOpening => openingTotal == 0.0;
  bool get canEnterManualClosing => closingTotal == 0.0;

  // --- EFFECTIVE DISPLAY AND REPORTING VALUES ---
  // If calculated opening is 0 and a manual float is saved, effectiveOpening reflects the float.
  // If calculated opening is non-zero, the natural calculated value is strictly preserved.
  double get effectiveOpeningCash =>
      (canEnterManualOpening && hasManualOpening)
          ? (manualOpeningCash ?? 0.0)
          : openingCash;

  double get effectiveOpeningUpi =>
      (canEnterManualOpening && hasManualOpening)
          ? (manualOpeningUpi ?? 0.0)
          : openingUpi;

  double get effectiveOpeningOther => openingOther;

  double get effectiveOpeningTotal =>
      effectiveOpeningCash + effectiveOpeningUpi + effectiveOpeningOther;

  // Effective Closing Balance:
  // Derived as Effective Opening + Sales - Expenses unless a verified manual closing override exists.
  double get effectiveClosingCash {
    if (canEnterManualClosing && manualClosingCash != null) {
      return manualClosingCash!;
    }
    return effectiveOpeningCash + salesCash - expensesCash;
  }

  double get effectiveClosingUpi {
    if (canEnterManualClosing && manualClosingUpi != null) {
      return manualClosingUpi!;
    }
    return effectiveOpeningUpi + salesUpi - expensesUpi;
  }

  double get effectiveClosingOther => closingOther;

  double get effectiveClosingTotal =>
      effectiveClosingCash + effectiveClosingUpi + effectiveClosingOther;
}

class SettlementTransactionItem {
  final String id;
  final DateTime timestamp;
  final String type; // 'sale' or 'expense'
  final String description;
  final String paymentMethod;
  final double amount;
  final String? reference;

  const SettlementTransactionItem({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.description,
    required this.paymentMethod,
    required this.amount,
    this.reference,
  });

  bool get isSale => type == 'sale';
  bool get isExpense => type == 'expense';

  double get cashAmount => paymentMethod.toLowerCase() == 'cash' ? amount : 0.0;
  double get upiAmount => paymentMethod.toLowerCase() == 'upi' ? amount : 0.0;
}

class SettlementMonthlyDay {
  final DateTime date;
  final double salesCash;
  final double salesUpi;
  final double salesOther;
  final double expensesCash;
  final double expensesUpi;
  final double expensesOther;

  const SettlementMonthlyDay({
    required this.date,
    this.salesCash = 0.0,
    this.salesUpi = 0.0,
    this.salesOther = 0.0,
    this.expensesCash = 0.0,
    this.expensesUpi = 0.0,
    this.expensesOther = 0.0,
  });

  double get salesTotal => salesCash + salesUpi + salesOther;
  double get expensesTotal => expensesCash + expensesUpi + expensesOther;

  double get netCash => salesCash - expensesCash;
  double get netUpi => salesUpi - expensesUpi;
  double get netOther => salesOther - expensesOther;
  double get netTotal => salesTotal - expensesTotal;
}
