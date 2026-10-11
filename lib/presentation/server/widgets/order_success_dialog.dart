import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Modal dialog presented after successful atomic order creation.
/// Displays generated order number, table, customer, and total.
/// Provides action: [Done] (return to Table Context).
class OrderSuccessDialog extends StatefulWidget {
  final String orderNumber;
  final String tableNumber;
  final String customerName;
  final double? totalAmount;
  final VoidCallback onDone;

  const OrderSuccessDialog({
    super.key,
    required this.orderNumber,
    required this.tableNumber,
    this.customerName = 'Customer',
    this.totalAmount,
    required this.onDone,
  });

  static Future<void> show({
    required BuildContext context,
    required String orderNumber,
    required String tableNumber,
    String customerName = 'Customer',
    double? totalAmount,
    required VoidCallback onDone,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrderSuccessDialog(
        orderNumber: orderNumber,
        tableNumber: tableNumber,
        customerName: customerName,
        totalAmount: totalAmount,
        onDone: onDone,
      ),
    );
  }

  @override
  State<OrderSuccessDialog> createState() => _OrderSuccessDialogState();
}

class _OrderSuccessDialogState extends State<OrderSuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusXL),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 480 ? 440 : MediaQuery.of(context).size.width * 0.92,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated Checkmark Icon
              ScaleTransition(
                scale: _scaleAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.secondaryGreen.withValues(alpha: 0.18),
                          AppColors.primaryGreen.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.secondaryGreen.withValues(alpha: 0.35),
                        width: 2,
                      ),
                      boxShadow: AppColors.glowGreen,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.secondaryGreen,
                      size: 50,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Order Placed Successfully',
                style: AppTextStyles.h3.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Order is registered and table remains active.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Order Details Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  children: [
                    _detailRow('Order Number', widget.orderNumber, bold: true),
                    const Divider(height: 16),
                    _detailRow('Table', widget.tableNumber),
                    const Divider(height: 16),
                    _detailRow('Customer', widget.customerName),
                    if (widget.totalAmount != null) ...[
                      const Divider(height: 16),
                      _detailRow(
                        'Total Amount',
                        '${AppConstants.defaultCurrencySymbol}${widget.totalAmount!.toStringAsFixed(0)}',
                        bold: true,
                        isHighlight: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Actions
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDone();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    'Done',
                    style: AppTextStyles.buttonText.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    bool bold = false,
    bool isHighlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: (bold ? AppTextStyles.labelLarge : AppTextStyles.bodyMedium).copyWith(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: isHighlight ? AppColors.primaryGreen : AppColors.primaryDark,
          ),
        ),
      ],
    );
  }
}
