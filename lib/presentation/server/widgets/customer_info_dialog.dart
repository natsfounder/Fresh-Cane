import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../state/server_order_provider.dart';

/// Modal dialog for fast tablet entry of Customer Name and 10-digit Mobile Number.
class CustomerInfoDialog extends ConsumerStatefulWidget {
  const CustomerInfoDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const CustomerInfoDialog(),
    );
  }

  @override
  ConsumerState<CustomerInfoDialog> createState() => _CustomerInfoDialogState();
}

class _CustomerInfoDialogState extends ConsumerState<CustomerInfoDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  bool _isLookingUp = false;

  @override
  void initState() {
    super.initState();
    final currentState = ref.read(serverOrderProvider);
    _nameController = TextEditingController(text: currentState.customerName);
    _phoneController = TextEditingController(text: currentState.customerPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handlePhoneChanged(String value) async {
    final cleaned = value.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length == 10 && _nameController.text.trim().isEmpty) {
      setState(() => _isLookingUp = true);
      try {
        final repo = ref.read(orderRepositoryProvider);
        final customer = await repo.fetchCustomerByPhone(cleaned);
        if (customer != null && customer.name != null && mounted) {
          _nameController.text = customer.name!;
          HapticFeedback.lightImpact();
        }
      } finally {
        if (mounted) setState(() => _isLookingUp = false);
      }
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    ref.read(serverOrderProvider.notifier).setCustomerInfo(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
        );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 460 ? 420 : MediaQuery.of(context).size.width * 0.92,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
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
                        color: AppColors.secondaryLight,
                        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                        border: Border.all(
                          color: AppColors.secondaryGreen.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.person_pin_rounded,
                        color: AppColors.primaryGreen,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customer Details',
                            style: AppTextStyles.h2.copyWith(
                              color: AppColors.primaryDark,
                            ),
                          ),
                          Text(
                            'Optional — for receipts & order history',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Mobile Number Field
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  style: AppTextStyles.bodyMedium,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    hintText: '9876543210',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                    prefixText: '+91  ',
                    prefixStyle: AppTextStyles.labelMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                    prefixIcon: const Icon(Icons.phone_iphone_rounded, color: AppColors.primaryGreen),
                    helperText: '10-digit Indian mobile number',
                    helperStyle: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                      borderSide: const BorderSide(color: AppColors.borderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                      borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.8),
                    ),
                    suffixIcon: _isLookingUp
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          )
                        : null,
                  ),
                  onChanged: _handlePhoneChanged,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return null; // Optional field
                    }
                    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(val.trim())) {
                      return 'Must be a valid 10-digit number starting with 6-9';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Customer Name Field
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(
                    labelText: 'Customer Name (Optional)',
                    hintText: 'e.g. Rahul Sharma',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                    prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primaryGreen),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                      borderSide: const BorderSide(color: AppColors.borderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                      borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.8),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.borderMedium),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Cancel',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Apply Details',
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
}
