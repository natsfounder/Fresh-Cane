import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../models/bill_model.dart';
import '../../../models/payment_model.dart';

/// Modal dialog showing completed tax receipt and print confirmation.
class ReceiptDialog extends StatelessWidget {
  final Bill bill;
  final Payment payment;
  final VoidCallback onFinish;

  const ReceiptDialog({
    super.key,
    required this.bill,
    required this.payment,
    required this.onFinish,
  });

  static Future<void> show(
    BuildContext context, {
    required Bill bill,
    required Payment payment,
    required VoidCallback onFinish,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReceiptDialog(
        bill: bill,
        payment: payment,
        onFinish: onFinish,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 520 ? 480 : MediaQuery.of(context).size.width * 0.92,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Success Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.secondaryGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.secondaryGreen,
                size: 48,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Payment Settled & Paid',
              style: AppTextStyles.h2.copyWith(color: AppColors.primaryDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Bill No: ${bill.billNumber}',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              AppDateTime.formatDateTime(bill.createdAt),
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const Divider(),

            // Store Snapshot Header
            const SizedBox(height: 8),
            Text(
              bill.storeNameSnapshot,
              style: AppTextStyles.h3.copyWith(color: AppColors.primaryDark),
              textAlign: TextAlign.center,
            ),
            if (bill.storeAddressSnapshot != null)
              Text(
                bill.storeAddressSnapshot!,
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),

            // Receipt Details Table
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                children: [
                  _buildRow('Subtotal', '₹${bill.subtotalAmount.toStringAsFixed(2)}'),
                  if (bill.discountAmount > 0)
                    _buildRow(
                      'Discount (${bill.discountType ?? 'Flat'})',
                      '- ₹${bill.discountAmount.toStringAsFixed(2)}',
                      textColor: AppColors.error,
                    ),
                  _buildRow('Tax (${bill.taxRateSnapshot}%)', '₹${bill.taxAmount.toStringAsFixed(2)}'),
                  const Divider(),
                  _buildRow(
                    'TOTAL PAID',
                    '₹${bill.finalAmount.toStringAsFixed(2)}',
                    isBold: true,
                    textColor: AppColors.primaryGreen,
                  ),
                  const SizedBox(height: 6),
                  _buildRow('Payment Method', payment.paymentMethod.toUpperCase()),
                  if (payment.paymentMethod == 'cash' && payment.cashTendered != null) ...[
                    _buildRow('Cash Tendered', '₹${payment.cashTendered!.toStringAsFixed(2)}'),
                    _buildRow('Change Returned', '₹${(payment.changeReturned ?? 0).toStringAsFixed(2)}'),
                  ],
                  if (payment.transactionReference != null && payment.transactionReference!.isNotEmpty)
                    _buildRow('Ref/UPI Txn ID', payment.transactionReference!),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Simulating receipt print to thermal printer...'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Print Receipt'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.primaryGreen),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onFinish();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Done & Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false, Color? textColor}) {
    final style = isBold
        ? AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.bold, color: textColor ?? AppColors.primaryDark)
        : AppTextStyles.bodySmall.copyWith(color: textColor ?? AppColors.textPrimary);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
