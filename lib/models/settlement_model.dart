/// Settlement Data Models for Fresh Cane POS
/// Supports Daily and Monthly payment-position settlement:
/// Opening Balance + Sales − Expenses = Closing Balance (Calculated independently per payment method)
class SettlementDailySummary {
  final DateTime date;
  final double openingCash;
  final double openingUpi;
  final double openingOther;
  final double salesCash;
  final double salesUpi;
  final double salesOther;
  final double expensesCash;
  final double expensesUpi;
  final double expensesOther;

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
  });

  double get openingTotal => openingCash + openingUpi + openingOther;
  double get salesTotal => salesCash + salesUpi + salesOther;
  double get expensesTotal => expensesCash + expensesUpi + expensesOther;

  double get closingCash => openingCash + salesCash - expensesCash;
  double get closingUpi => openingUpi + salesUpi - expensesUpi;
  double get closingOther => openingOther + salesOther - expensesOther;
  double get closingTotal => openingTotal + salesTotal - expensesTotal;

  double get netCash => salesCash - expensesCash;
  double get netUpi => salesUpi - expensesUpi;
  double get netTotal => salesTotal - expensesTotal;
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
