import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/models.dart';

/// Modal dialog allowing Cashier to inspect the order summary,
/// view bill total, and confirm tax bill generation.
class BillSummaryDialog extends StatefulWidget {
  final SessionOrderSummary order;
  final String customerName;

  const BillSummaryDialog({
    super.key,
    required this.order,
    required this.customerName,
  });

  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    required SessionOrderSummary order,
    required String customerName,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BillSummaryDialog(
        order: order,
        customerName: customerName,
      ),
    );
  }

  @override
  State<BillSummaryDialog> createState() => _BillSummaryDialogState();
}

class _BillSummaryDialogState extends State<BillSummaryDialog> {
  double get _subtotal => widget.order.totalAmount;

  void _onGenerateBill() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop({
      'discount_type': null,
      'discount_value': 0.0,
      'discount_reason': null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogMaxHeight = media.size.height * 0.85;
    final dialogMaxWidth = media.size.width > 520 ? 460.0 : media.size.width * 0.92;

    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth,
          maxHeight: dialogMaxHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
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
                        Icons.receipt_long_rounded,
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
                            'Generate Bill',
                            style: AppTextStyles.h2.copyWith(
                              color: AppColors.primaryDark,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Order ${widget.order.orderNumber} • ${widget.customerName}',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 16),

                // Subtotal & Items Breakdown Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    children: [
                      _row('Order Subtotal', '${AppConstants.defaultCurrencySymbol}${_subtotal.toStringAsFixed(0)}'),
                      if (widget.order.itemsSummary.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _row('Items', widget.order.itemsSummary, isCaption: true),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 14),

                // Final Bill Payable Row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total Bill Amount',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${AppConstants.defaultCurrencySymbol}${_subtotal.toStringAsFixed(0)}',
                      style: AppTextStyles.h2.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _onGenerateBill,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF266540),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                          shadowColor: const Color(0xFF266540).withValues(alpha: 0.3),
                        ),
                        child: Text(
                          'Generate Bill',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
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
    );
  }

  Widget _row(String label, String value, {bool isCaption = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: isCaption
              ? AppTextStyles.caption.copyWith(color: AppColors.textSecondary)
              : AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: isCaption
                ? AppTextStyles.caption.copyWith(color: AppColors.primaryDark)
                : AppTextStyles.h4.copyWith(color: AppColors.primaryDark),
          ),
        ),
      ],
    );
  }
}
