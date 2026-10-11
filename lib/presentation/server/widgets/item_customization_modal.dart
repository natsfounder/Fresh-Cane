import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/models.dart';
import '../../common/product_image_widget.dart';

/// Bottom sheet modal to customize an item with Add-ons, Parcel packaging, and instructions.
class ItemCustomizationModal extends StatefulWidget {
  final MenuItem item;
  final CartItem? initialCartItem;
  final List<MenuAddon> availableAddons;
  final void Function(CartItem configuredItem) onSave;

  const ItemCustomizationModal({
    super.key,
    required this.item,
    this.initialCartItem,
    required this.availableAddons,
    required this.onSave,
  });

  static Future<void> show({
    required BuildContext context,
    required MenuItem item,
    CartItem? initialCartItem,
    required List<MenuAddon> availableAddons,
    required void Function(CartItem configuredItem) onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ItemCustomizationModal(
        item: item,
        initialCartItem: initialCartItem,
        availableAddons: availableAddons,
        onSave: onSave,
      ),
    );
  }

  @override
  State<ItemCustomizationModal> createState() => _ItemCustomizationModalState();
}

class _ItemCustomizationModalState extends State<ItemCustomizationModal> {
  late int _quantity;
  late bool _isParcel;
  late List<MenuAddon> _selectedAddons;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialCartItem?.quantity ?? 1;
    _isParcel = widget.initialCartItem?.isParcel ?? false;
    _selectedAddons = List<MenuAddon>.from(
        widget.initialCartItem?.selectedAddons ?? const []);
    _notesController = TextEditingController(
      text: widget.initialCartItem?.specialInstructions ?? '',
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  double get _addonsTotalPerUnit =>
      _selectedAddons.fold(0.0, (sum, a) => sum + a.price);

  double get _effectiveUnitPrice => widget.item.basePrice + _addonsTotalPerUnit;

  double get _lineTotal => _effectiveUnitPrice * _quantity;

  void _toggleAddon(MenuAddon addon) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedAddons.any((a) => a.id == addon.id)) {
        _selectedAddons.removeWhere((a) => a.id == addon.id);
      } else {
        _selectedAddons.add(addon);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 20,
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header: Item name + base price + close
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProductImageWidget(
                imageUrl: widget.item.imageUrl,
                width: 52,
                height: 52,
                borderRadius: BorderRadius.circular(10),
                fit: BoxFit.cover,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name,
                      style: AppTextStyles.h2.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Base Price: ${AppConstants.defaultCurrencySymbol}${widget.item.basePrice.toStringAsFixed(0)}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.borderLight),

          // Scrollable options
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── 1. Dining Option (Dine-In vs Parcel) ─────────────
                  Text(
                    'Order Option (Dine-In or Parcel)',
                    style: AppTextStyles.labelMedium.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isParcel = false);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !_isParcel
                                  ? AppColors.primaryLight
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: !_isParcel
                                    ? AppColors.primaryGreen
                                    : AppColors.borderLight,
                                width: !_isParcel ? 1.8 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.table_restaurant_rounded,
                                  size: 18,
                                  color: !_isParcel
                                      ? AppColors.primaryDark
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Dine-In (Table)',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: !_isParcel
                                        ? AppColors.primaryDark
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isParcel = true);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _isParcel
                                  ? const Color(0xFFFFF7ED)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _isParcel
                                    ? const Color(0xFFEA580C)
                                    : AppColors.borderLight,
                                width: _isParcel ? 1.8 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inventory_2_rounded,
                                  size: 18,
                                  color: _isParcel
                                      ? const Color(0xFFEA580C)
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '📦 Parcel (To-Go)',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: _isParcel
                                        ? const Color(0xFFEA580C)
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ─── 2. Add-ons Section ─────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Add-ons',
                        style: AppTextStyles.labelMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      Text(
                        'Optional extra flavours',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Builder(
                    builder: (context) {
                      final productAddons = widget.availableAddons
                          .where((a) => a.menuItemId == widget.item.id)
                          .toList();

                      if (productAddons.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderLight),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: AppColors.textSecondary.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No add-ons available for this product',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: productAddons.map((addon) {
                          final isSelected =
                              _selectedAddons.any((a) => a.id == addon.id);

                          return FilterChip(
                            selected: isSelected,
                            onSelected: (_) => _toggleAddon(addon),
                            label: Text(
                              '${addon.name} (+${AppConstants.defaultCurrencySymbol}${addon.price.toStringAsFixed(0)})',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.primaryDark,
                              ),
                            ),
                            selectedColor: AppColors.primaryGreen,
                            backgroundColor: AppColors.primaryLight,
                            checkmarkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primaryGreen
                                    : AppColors.primaryGreen
                                        .withValues(alpha: 0.3),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // ─── 3. Quantity Stepper ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Quantity',
                        style: AppTextStyles.labelMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_rounded, size: 18),
                              onPressed: _quantity > 1
                                  ? () {
                                      HapticFeedback.lightImpact();
                                      setState(() => _quantity--);
                                    }
                                  : null,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                '$_quantity',
                                style: AppTextStyles.h4.copyWith(
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_rounded, size: 18),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setState(() => _quantity++);
                              },
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── 4. Special Instructions ────────────────────────
                  Text(
                    'Special Instructions (Optional)',
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Less ice, no sugar, extra chilled...',
                      hintStyle: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppColors.borderLight),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ─── 5. Real-time Price Calculation Breakdown ─────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.secondaryGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Base Item Price',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              '₹${widget.item.basePrice.toStringAsFixed(0)}',
                              style: AppTextStyles.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                        if (_selectedAddons.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  'Add-ons (${_selectedAddons.length}): ${_selectedAddons.map((a) => a.name).join(", ")}',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primaryGreen,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '+₹${_addonsTotalPerUnit.toStringAsFixed(0)}',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.primaryGreen,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 12, color: AppColors.borderLight),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Unit: ₹${_effectiveUnitPrice.toStringAsFixed(0)} × $_quantity qty',
                              style: AppTextStyles.labelMedium.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            Text(
                              '₹${_lineTotal.toStringAsFixed(0)}',
                              style: AppTextStyles.h3.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Total & Save Button
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Amount',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${AppConstants.defaultCurrencySymbol}${_lineTotal.toStringAsFixed(0)}',
                    style: AppTextStyles.moneyLarge.copyWith(
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  final configured = CartItem(
                    menuItem: widget.item,
                    quantity: _quantity,
                    selectedAddons: _selectedAddons,
                    isParcel: _isParcel,
                    specialInstructions: _notesController.text.trim().isNotEmpty
                        ? _notesController.text.trim()
                        : null,
                  );
                  widget.onSave(configured);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Add to Order'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}
