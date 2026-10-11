import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/models.dart';
import '../../../models/payment_method_model.dart';
import '../../../state/payment_method_provider.dart';

/// Modal dialog allowing Cashier to settle payment for a generated bill
/// with support for configurable payment methods (Cash, UPI, Card, etc.) or Split Tender.
class PaymentDialog extends ConsumerStatefulWidget {
  final Bill bill;

  const PaymentDialog({
    super.key,
    required this.bill,
  });

  static Future<List<Map<String, dynamic>>?> show({
    required BuildContext context,
    required Bill bill,
  }) {
    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PaymentDialog(bill: bill),
    );
  }

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  String _paymentMode = 'cash'; // 'cash', 'upi', 'card', 'split'
  final _cashTenderedController = TextEditingController();
  final _upiRefController = TextEditingController();

  // Split mode controllers
  final _splitCashAmountController = TextEditingController();
  final _splitCashTenderedController = TextEditingController();
  final _splitUpiAmountController = TextEditingController();
  final _splitUpiRefController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _cashTenderedController.text = widget.bill.finalAmount.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _cashTenderedController.dispose();
    _upiRefController.dispose();
    _splitCashAmountController.dispose();
    _splitCashTenderedController.dispose();
    _splitUpiAmountController.dispose();
    _splitUpiRefController.dispose();
    super.dispose();
  }

  double get _finalBillAmount => widget.bill.finalAmount;

  double get _cashTendered =>
      double.tryParse(_cashTenderedController.text.trim()) ?? 0.0;

  double get _changeReturned {
    if (_paymentMode != 'cash') return 0.0;
    final diff = _cashTendered - _finalBillAmount;
    return diff > 0 ? diff : 0.0;
  }

  double get _splitCashTendered =>
      double.tryParse(_splitCashTenderedController.text.trim()) ?? 0.0;

  double get _splitCashAmount =>
      double.tryParse(_splitCashAmountController.text.trim()) ?? 0.0;

  double get _splitChangeReturned {
    final diff = _splitCashTendered - _splitCashAmount;
    return diff > 0 ? diff : 0.0;
  }

  void _onSettlePayment() {
    if (!_formKey.currentState!.validate()) return;

    List<Map<String, dynamic>> payments = [];

    if (_paymentMode == 'cash') {
      payments.add({
        'method': 'cash',
        'amount': _finalBillAmount,
        'cash_tendered': _cashTendered,
        'transaction_reference': null,
      });
    } else if (_paymentMode == 'split') {
      final cashAmt = _splitCashAmount;
      final upiAmt = double.tryParse(_splitUpiAmountController.text.trim()) ?? 0.0;

      if ((cashAmt + upiAmt) != _finalBillAmount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Split total (₹${(cashAmt + upiAmt).toStringAsFixed(0)}) must equal bill final amount (₹${_finalBillAmount.toStringAsFixed(0)})',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      if (cashAmt > 0) {
        payments.add({
          'method': 'cash',
          'amount': cashAmt,
          'cash_tendered': _splitCashTendered,
          'transaction_reference': null,
        });
      }

      if (upiAmt > 0) {
        payments.add({
          'method': 'upi',
          'amount': upiAmt,
          'transaction_reference': _splitUpiRefController.text.trim().isNotEmpty
              ? _splitUpiRefController.text.trim()
              : null,
        });
      }
    } else {
      payments.add({
        'method': _paymentMode,
        'amount': _finalBillAmount,
        'transaction_reference': _upiRefController.text.trim().isNotEmpty
            ? _upiRefController.text.trim()
            : null,
      });
    }

    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(payments);
  }

  @override
  Widget build(BuildContext context) {
    final enabledMethods = ref.watch(enabledPaymentMethodsProvider);
    if (_paymentMode != 'split' && !enabledMethods.any((m) => m.id == _paymentMode)) {
      _paymentMode = enabledMethods.isNotEmpty ? enabledMethods.first.id : 'cash';
    }

    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 560 ? 520 : MediaQuery.of(context).size.width * 0.92,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryGreen.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.payments_rounded,
                          color: AppColors.secondaryGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Settle Payment',
                              style: AppTextStyles.h2.copyWith(
                                color: AppColors.primaryDark,
                              ),
                            ),
                            Text(
                              'Bill ${widget.bill.billNumber} • Amount: ${AppConstants.defaultCurrencySymbol}${_finalBillAmount.toStringAsFixed(0)}',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.secondaryGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.borderLight),
                  const SizedBox(height: 16),

                  // Payment Method Toggle Chips
                  Text('SELECT PAYMENT METHOD', style: AppTextStyles.overline),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...enabledMethods.map((m) {
                        return ChoiceChip(
                          avatar: Icon(m.icon, size: 18),
                          label: Text(m.name),
                          selected: _paymentMode == m.id,
                          selectedColor: const Color(0xFF266540),
                          labelStyle: TextStyle(
                            color: _paymentMode == m.id ? Colors.white : AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _paymentMode = m.id);
                          },
                        );
                      }),
                      if (enabledMethods.any((m) => m.id == 'cash') && enabledMethods.any((m) => m.id == 'upi'))
                        ChoiceChip(
                          avatar: const Icon(Icons.call_split_rounded, size: 18),
                          label: const Text('Split (Cash + UPI)'),
                          selected: _paymentMode == 'split',
                          selectedColor: const Color(0xFF266540),
                          labelStyle: TextStyle(
                            color: _paymentMode == 'split' ? Colors.white : AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _paymentMode = 'split';
                                if (_splitCashAmountController.text.isEmpty) {
                                  final half = (_finalBillAmount / 2).roundToDouble();
                                  _splitCashAmountController.text = half == half.roundToDouble() ? half.toStringAsFixed(0) : half.toStringAsFixed(2);
                                  _splitCashTenderedController.text = _splitCashAmountController.text;
                                  final upi = _finalBillAmount - half;
                                  _splitUpiAmountController.text = upi == upi.roundToDouble() ? upi.toStringAsFixed(0) : upi.toStringAsFixed(2);
                                }
                              });
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Mode Details
                  if (_paymentMode == 'cash') ...[
                    TextFormField(
                      controller: _cashTenderedController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: AppTextStyles.h3.copyWith(color: AppColors.primaryDark),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Cash Tendered (₹)',
                        hintText: 'e.g. 500',
                        prefixIcon: const Icon(Icons.numbers_rounded, color: AppColors.secondaryGreen),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        ),
                      ),
                      validator: (val) {
                        final amt = double.tryParse(val?.trim() ?? '');
                        if (amt == null || amt < _finalBillAmount) {
                          return 'Cash tendered must be at least ${AppConstants.defaultCurrencySymbol}${_finalBillAmount.toStringAsFixed(0)}';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        border: Border.all(color: AppColors.secondaryGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Change to Return', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryDark)),
                          Text(
                            '${AppConstants.defaultCurrencySymbol}${_changeReturned.toStringAsFixed(0)}',
                            style: AppTextStyles.h2.copyWith(
                              color: AppColors.secondaryGreen,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_paymentMode != 'split') ...[
                    TextFormField(
                      controller: _upiRefController,
                      style: AppTextStyles.bodyMedium,
                      decoration: InputDecoration(
                        labelText: '${enabledMethods.firstWhere((m) => m.id == _paymentMode, orElse: () => PaymentMethodItem(id: _paymentMode, name: _paymentMode.toUpperCase(), isEnabled: true)).name} Reference / Transaction ID (Optional)',
                        hintText: 'e.g. UPI / Auth Ref No.',
                        prefixIcon: const Icon(Icons.receipt_rounded, color: AppColors.secondaryGreen),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        ),
                      ),
                    ),
                  ] else if (_paymentMode == 'split') ...[
                    TextFormField(
                      controller: _splitCashAmountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: AppTextStyles.bodyMedium,
                      onChanged: (val) {
                        final cashAmt = double.tryParse(val.trim());
                        if (cashAmt != null && cashAmt >= 0 && cashAmt <= _finalBillAmount) {
                          final upi = _finalBillAmount - cashAmt;
                          _splitUpiAmountController.text = upi == upi.roundToDouble() ? upi.toStringAsFixed(0) : upi.toStringAsFixed(2);
                          _splitCashTenderedController.text = cashAmt == cashAmt.roundToDouble() ? cashAmt.toStringAsFixed(0) : cashAmt.toStringAsFixed(2);
                        }
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        labelText: 'Cash Amount (₹)',
                        hintText: 'e.g. 100',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        ),
                      ),
                      validator: (val) {
                        final amt = double.tryParse(val?.trim() ?? '');
                        if (amt == null || amt < 0 || amt > _finalBillAmount) {
                          return 'Enter valid cash portion (0 - ${_finalBillAmount.toStringAsFixed(0)})';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _splitCashTenderedController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: AppTextStyles.bodyMedium,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Cash Tendered (₹)',
                        hintText: 'e.g. 100',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        ),
                      ),
                      validator: (val) {
                        final amt = double.tryParse(val?.trim() ?? '');
                        if (amt == null || amt < _splitCashAmount) {
                          return 'Cash tendered must be >= Cash Amount';
                        }
                        return null;
                      },
                    ),
                    if (_splitChangeReturned > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Change to Return: ${AppConstants.defaultCurrencySymbol}${_splitChangeReturned.toStringAsFixed(0)}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.secondaryGreen, fontWeight: FontWeight.bold),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _splitUpiAmountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: AppTextStyles.bodyMedium,
                      onChanged: (val) {
                        final upiAmt = double.tryParse(val.trim());
                        if (upiAmt != null && upiAmt >= 0 && upiAmt <= _finalBillAmount) {
                          final cash = _finalBillAmount - upiAmt;
                          _splitCashAmountController.text = cash == cash.roundToDouble() ? cash.toStringAsFixed(0) : cash.toStringAsFixed(2);
                          _splitCashTenderedController.text = _splitCashAmountController.text;
                        }
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        labelText: 'UPI Amount (₹)',
                        hintText: 'e.g. 100',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        ),
                      ),
                      validator: (val) {
                        final amt = double.tryParse(val?.trim() ?? '');
                        if (amt == null || amt < 0 || amt > _finalBillAmount) {
                          return 'Enter valid UPI portion';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _splitUpiRefController,
                      style: AppTextStyles.bodyMedium,
                      decoration: InputDecoration(
                        labelText: 'UPI Transaction Reference (Optional)',
                        hintText: 'Ref No.',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(null),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                            ),
                          ),
                          child: Text(
                            'Back',
                            style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _onSettlePayment,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF266540),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 2,
                            shadowColor: const Color(0xFF266540).withValues(alpha: 0.4),
                          ),
                          child: const Text(
                            'Pay & Complete',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
