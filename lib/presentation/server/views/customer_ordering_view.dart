import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/responsive.dart';
import '../../../models/models.dart';
import '../../../state/server_order_provider.dart';
import '../widgets/item_customization_modal.dart';
import '../widgets/order_review_dialog.dart';
import '../widgets/order_success_dialog.dart';
import '../../common/product_image_widget.dart';

/// Step 3 / Dedicated Order Screen: Categories -> Menu Items -> Cart.
///
/// Features:
/// - Header: Back button (returns to Tables Screen) + Table/seating label.
/// - Left panel: Vertical list of menu categories (highlighted in Teal 50 / Teal 800).
/// - Right panel: Grid of menu item cards for the selected category.
/// - Inline Add Control: Swiggy/Zomato-style cart stepper directly on the item card
///   with smooth ~150ms scale/fade transition.
/// - Bottom bar: Persistent docked running summary with item count, total price, and "Review order" button.
class CustomerOrderingView extends ConsumerWidget {
  const CustomerOrderingView({super.key});

  void _handleBack(BuildContext context, WidgetRef ref, ServerOrderState state) {
    HapticFeedback.lightImpact();
    if (state.cart.isNotEmpty) {
      final isEditing = state.isEditingOrder;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          ),
          title: Text(isEditing ? 'Discard edits?' : 'Discard order?', style: AppTextStyles.h2),
          content: Text(
            isEditing
                ? 'You have unsaved changes to Order ${state.editingOrderNumber}. Are you sure you want to discard these edits and return to the table context?'
                : 'You have unplaced items in the cart. Are you sure you want to discard this order draft and return to the table context?',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Stay',
                  style: TextStyle(color: AppColors.primaryGreen)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppColors.radiusSmall),
                ),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.read(serverOrderProvider.notifier).returnToTableContext();
              },
              child: const Text('Discard & back'),
            ),
          ],
        ),
      );
    } else {
      ref.read(serverOrderProvider.notifier).returnToTableContext();
    }
  }

  void _handleReviewOrder(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final isEditing = ref.read(serverOrderProvider).isEditingOrder;
    final orderNum = ref.read(serverOrderProvider).editingOrderNumber;
    final result = await OrderReviewDialog.show(context);

    if (result == true && context.mounted) {
      final orderState = ref.read(serverOrderProvider);
      final submitted = orderState.submittedOrderResult;

      if (isEditing) {
        ref.read(serverOrderProvider.notifier).returnToTableContext();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✓ Order ${orderNum ?? ""} updated successfully!',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.primaryDark,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
            ),
          ),
        );
      } else if (submitted != null) {
        final orderNumber = submitted['order_number'] as String? ?? 'ORD';
        final total = (submitted['total_amount'] as num?)?.toDouble() ??
            orderState.grandTotalAmount;

        await OrderSuccessDialog.show(
          context: context,
          orderNumber: orderNumber,
          totalAmount: total,
          tableNumber: orderState.activeTable?.tableNumber ?? '',
          customerName: orderState.selectedCustomer?.displayName ?? 'Customer',
          onDone: () {
            ref
                .read(serverOrderProvider.notifier)
                .returnToTableContext();
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderState = ref.watch(serverOrderProvider);
    final table = orderState.activeTable;
    final customer = orderState.selectedCustomer;

    if (table == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No table selected'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref
                    .read(serverOrderProvider.notifier)
                    .returnToTableSelection(),
                child: const Text('Return to tables'),
              ),
            ],
          ),
        ),
      );
    }

    // Determine seating label (e.g. "Table 4 · Seating 2")
    final seatingText = customer != null
        ? customer.displayName
        : 'Seating 1';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // ─── 1. Header: Back + Table/Seating Label ─────────────────────────
          Container(
            height: Responsive.headerHeight(context),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: AppColors.cardSurface,
              border: Border(
                bottom: BorderSide(color: AppColors.borderLight, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Material(
                  color: Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(AppColors.radiusSmall),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusSmall),
                    onTap: () => _handleBack(context, ref, orderState),
                    child: Container(
                      width: AppColors.minTouchTarget,
                      height: AppColors.minTouchTarget,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Table & Seating Label + Edit Mode Indicator
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Table ${table.tableNumber} · $seatingText',
                        style: AppTextStyles.h4.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: Responsive.isCompact(context) ? 14 : 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (orderState.isEditingOrder)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.primaryGreen
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.edit_note_rounded,
                                    size: 13, color: AppColors.primaryDark),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    'EDITING ${orderState.editingOrderNumber ?? "ORDER"}',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.primaryDark,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Dining Mode Toggle: [ 🍽️ Dine-In | 📦 Parcel ]
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref
                              .read(serverOrderProvider.notifier)
                              .setDefaultDiningMode(false);
                        },
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(20)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: !orderState.defaultDiningModeIsParcel
                                ? AppColors.primaryGreen
                                : Colors.transparent,
                            borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(19)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.restaurant_rounded,
                                size: 12,
                                color: !orderState.defaultDiningModeIsParcel
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Dine',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: !orderState.defaultDiningModeIsParcel
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref
                              .read(serverOrderProvider.notifier)
                              .setDefaultDiningMode(true);
                        },
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(20)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: orderState.defaultDiningModeIsParcel
                                ? const Color(0xFFEA580C)
                                : Colors.transparent,
                            borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(19)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 12,
                                color: orderState.defaultDiningModeIsParcel
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Parcel',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: orderState.defaultDiningModeIsParcel
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Live Cart Item Indicator Pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: orderState.totalItemsCount > 0
                        ? AppColors.primaryLight
                        : AppColors.warmSurface,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusRound),
                    border: Border.all(
                      color: orderState.totalItemsCount > 0
                          ? AppColors.primaryGreen.withValues(alpha: 0.3)
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 14,
                        color: orderState.totalItemsCount > 0
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        orderState.totalItemsCount == 1
                            ? '1 item'
                            : '${orderState.totalItemsCount} items',
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: orderState.totalItemsCount > 0
                              ? AppColors.primaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── 2. Main Layout: Categories (Left) + Menu Items (Center) + Live Cart (Right on Tablet Landscape)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isThreePane = constraints.maxWidth >= 840;
                final categoryWidth =
                    Responsive.categoryPanelWidth(context);
                final isCompact = Responsive.isCompact(context);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Pane 1: Left Panel - Vertical Category List (ALWAYS on the left)
                    SizedBox(
                      width: categoryWidth,
                      child: _CategoryLeftPanel(isCompact: isCompact),
                    ),

                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColors.borderLight,
                    ),

                    // Pane 2: Center Panel - Menu Items Grid
                    const Expanded(
                      child: _MenuItemsRightPanel(),
                    ),

                    // Pane 3: Tablet Landscape Right Panel - Live Order Summary
                    if (isThreePane) ...[
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppColors.borderLight,
                      ),
                      SizedBox(
                        width: 320,
                        child: _TabletCartSummaryPanel(
                          onReview: () => _handleReviewOrder(context, ref),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),

          // ─── 3. Persistent Docked Bottom Bar (Visible on mobile / 2-pane mode) ──
          LayoutBuilder(
            builder: (context, constraints) {
              final isThreePane = MediaQuery.sizeOf(context).width >= 840;
              if (isThreePane) return const SizedBox.shrink();
              return _OrderBottomBar(
                totalCount: orderState.totalItemsCount,
                parcelCount: orderState.parcelItemsCount,
                totalPrice: orderState.grandTotalAmount,
                canSubmit: orderState.canSubmitOrder,
                isEditing: orderState.isEditingOrder,
                onReview: () => _handleReviewOrder(context, ref),
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LEFT PANEL: CATEGORIES (Wood-tinted glass, clean minimal list)
// =============================================================================

class _CategoryLeftPanel extends ConsumerWidget {
  final bool isCompact;

  const _CategoryLeftPanel({this.isCompact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderState = ref.watch(serverOrderProvider);
    final categories = orderState.categories;
    final selectedCategoryId = orderState.selectedCategoryId;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F2E1E),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : 14,
              vertical: 13,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF265036), width: 1),
              ),
            ),
            child: Text(
              'Categories',
              style: TextStyle(
                color: Colors.white,
                fontSize: isCompact ? 11 : 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Categories List
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                vertical: 8,
                horizontal: isCompact ? 4 : 8,
              ),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final category = categories[index];
                final isSelected = selectedCategoryId == category.id;

                final imageAsset = category.imageUrl != null &&
                        category.imageUrl!.isNotEmpty
                    ? category.imageUrl!
                    : 'assets/images/categories/${category.slug}.png';

                return Material(
                  color: isSelected
                      ? const Color(0xFF266540)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref
                          .read(serverOrderProvider.notifier)
                          .selectCategory(category.id);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 6 : 10,
                        vertical: isCompact ? 8 : 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: isCompact
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    imageAsset,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.restaurant_rounded,
                                      size: 18,
                                      color: Color(0xFF0F2E1E),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  category.name,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFFB4C8BA),
                                    height: 1.15,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.white,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    imageAsset,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.restaurant_rounded,
                                      size: 18,
                                      color: Color(0xFF0F2E1E),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    category.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFFB4C8BA),
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// RIGHT PANEL: MENU ITEMS (Swiggy/Zomato Inline Stepper on Cards)
// =============================================================================

class _MenuItemsRightPanel extends ConsumerStatefulWidget {
  const _MenuItemsRightPanel();

  @override
  ConsumerState<_MenuItemsRightPanel> createState() => _MenuItemsRightPanelState();
}

class _MenuItemsRightPanelState extends ConsumerState<_MenuItemsRightPanel> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderState = ref.watch(serverOrderProvider);
    final items = orderState.filteredMenuItems;
    final isSearching = orderState.searchQuery != null &&
        orderState.searchQuery!.trim().isNotEmpty;

    // Sync controller if external action (like category click) cleared the search
    if (!isSearching && _searchController.text.isNotEmpty) {
      _searchController.clear();
    }

    return Column(
      children: [
        // ─── Search Bar ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.borderLight, width: 1),
            ),
          ),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppColors.radiusMedium),
              border: Border.all(
                color: isSearching
                    ? AppColors.primaryGreen
                    : AppColors.borderLight,
                width: isSearching ? 1.5 : 1,
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                ref
                    .read(serverOrderProvider.notifier)
                    .setSearchQuery(val.trim());
              },
              decoration: InputDecoration(
                hintText: 'Search all menu items...',
                hintStyle: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                  fontSize: 12.5,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.primaryDark,
                ),
                suffixIcon: isSearching
                    ? IconButton(
                        icon: const Icon(
                          Icons.cancel_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(serverOrderProvider.notifier)
                              .clearSearchQuery();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
              ),
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
            ),
          ),
        ),

        // ─── Active Search Feedback Banner ──────────────────────────
        if (isSearching)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: AppColors.primaryLight.withValues(alpha: 0.4),
            child: Row(
              children: [
                const Icon(
                  Icons.manage_search_rounded,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Found ${items.length} ${items.length == 1 ? "item" : "items"} for "${orderState.searchQuery}"',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    _searchController.clear();
                    ref
                        .read(serverOrderProvider.notifier)
                        .clearSearchQuery();
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Clear',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ─── Items Grid or Empty State ──────────────────────────────
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSearching
                              ? Icons.search_off_rounded
                              : Icons.restaurant_rounded,
                          size: 48,
                          color: AppColors.textSecondary
                              .withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isSearching
                              ? 'No items found matching "${orderState.searchQuery}"'
                              : 'No items available in this category',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isSearching) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: AppColors.primaryGreen
                                      .withValues(alpha: 0.5)),
                              foregroundColor: AppColors.primaryDark,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ),
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            label: const Text('Clear search'),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(serverOrderProvider.notifier)
                                  .clearSearchQuery();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth >= 520
                        ? 3
                        : (constraints.maxWidth >= 310 ? 2 : 1);

                    final aspectRatio = crossAxisCount == 1
                        ? 2.3
                        : (crossAxisCount == 2 ? 0.65 : 0.72);

                    final spacing = Responsive.gridSpacing(context);

                    return GridView.builder(
                      padding: Responsive.screenPadding(context),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: aspectRatio,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final cartItem = orderState.cart[item.id];
                        final quantity = cartItem?.quantity ?? 0;

                        return _MenuItemCard(
                          item: item,
                          cartItem: cartItem,
                          quantity: quantity,
                          onAdd: () {
                            HapticFeedback.lightImpact();
                            ref
                                .read(serverOrderProvider.notifier)
                                .addItem(item);
                          },
                          onDecrement: () {
                            HapticFeedback.lightImpact();
                            ref
                                .read(serverOrderProvider.notifier)
                                .decrementItem(item.id);
                          },
                          onCustomize: () {
                            HapticFeedback.lightImpact();
                            ItemCustomizationModal.show(
                              context: context,
                              item: item,
                              initialCartItem: cartItem,
                              availableAddons:
                                  orderState.availableAddons,
                              onSave: (configuredItem) {
                                ref
                                    .read(serverOrderProvider.notifier)
                                    .setConfiguredItem(configuredItem);
                              },
                            );
                          },
                          isSingleColumn: crossAxisCount == 1,
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Menu Item Card featuring the Swiggy/Zomato-style inline Add / Stepper control.
class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final CartItem? cartItem;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onDecrement;
  final VoidCallback onCustomize;
  final bool isSingleColumn;

  const _MenuItemCard({
    required this.item,
    this.cartItem,
    required this.quantity,
    required this.onAdd,
    required this.onDecrement,
    required this.onCustomize,
    this.isSingleColumn = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasAddons = cartItem != null && cartItem!.selectedAddons.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCustomize,
        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
        child: Container(
          padding: EdgeInsets.all(Responsive.isCompact(context) ? 8 : 10),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(AppColors.radiusMedium),
            border: Border.all(
              color: quantity > 0
                  ? AppColors.secondaryGreen.withValues(alpha: 0.3)
                  : AppColors.borderLight,
              width: 1,
            ),
            boxShadow: [
              ...AppColors.shadowSmall,
              if (quantity > 0)
                BoxShadow(
                  color: AppColors.secondaryGreen.withValues(alpha: 0.08),
                  blurRadius: 8,
                  spreadRadius: -2,
                ),
            ],
          ),
          child: isSingleColumn
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Product Photo Thumbnail
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusSmall),
                      child: ProductImageWidget(
                        imageUrl: item.imageUrl,
                        width: 66,
                        height: 66,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Details Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.name,
                            style: AppTextStyles.h4.copyWith(
                              letterSpacing: -0.1,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.description != null &&
                              item.description!.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              item.description!,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (cartItem != null &&
                              (cartItem!.isParcel || hasAddons)) ...[
                            const SizedBox(height: 2),
                            _buildBadges(hasAddons),
                          ],
                          const SizedBox(height: 4),
                          _buildPriceAndStepper(context, hasAddons),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top: Product Photo
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusSmall),
                      child: ProductImageWidget(
                        imageUrl: item.imageUrl,
                        height: Responsive.isCompact(context) ? 72 : 88,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 5),

                    // Item Name + Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.name,
                            style: AppTextStyles.h4.copyWith(
                              letterSpacing: -0.1,
                              fontSize:
                                  Responsive.isCompact(context) ? 12 : 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.description != null &&
                              item.description!.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              item.description!,
                              style: AppTextStyles.caption.copyWith(
                                fontSize:
                                    Responsive.isCompact(context) ? 9 : 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (cartItem != null &&
                        (cartItem!.isParcel || hasAddons)) ...[
                      const SizedBox(height: 2),
                      _buildBadges(hasAddons),
                    ],
                    const SizedBox(height: 4),
                    _buildPriceAndStepper(context, hasAddons),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildBadges(bool hasAddons) {
    if (cartItem == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cartItem!.isParcel) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: const Text(
                '📦 PARCEL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFEA580C),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (hasAddons)
            ...cartItem!.selectedAddons.map(
              (addon) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.primaryGreen.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '+${addon.name} (+₹${addon.price.toStringAsFixed(0)})',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPriceAndStepper(BuildContext context, bool hasAddons) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Price Breakdown
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (quantity == 0) ...[
                Text(
                  '₹${item.basePrice.toStringAsFixed(0)}',
                  style: AppTextStyles.moneySmall.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: Responsive.isCompact(context) ? 12 : 14,
                  ),
                ),
                const Text(
                  'Tap to customise',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ] else if (quantity == 1) ...[
                Text(
                  '₹${cartItem!.itemTotal.toStringAsFixed(0)}',
                  style: AppTextStyles.moneySmall.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: Responsive.isCompact(context) ? 12 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (hasAddons)
                  Text(
                    '₹${item.basePrice.toStringAsFixed(0)} + ₹${cartItem!.addonsPricePerUnit.toStringAsFixed(0)} add-on',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryGreen,
                    ),
                  )
                else
                  const Text(
                    'Customise ›',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryGreen,
                    ),
                  ),
              ] else ...[
                Text(
                  '₹${cartItem!.itemTotal.toStringAsFixed(0)}',
                  style: AppTextStyles.moneySmall.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: Responsive.isCompact(context) ? 12 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '₹${cartItem!.effectiveUnitPrice.toStringAsFixed(0)} ea${hasAddons ? " (incl. add-on)" : ""}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: hasAddons
                        ? AppColors.primaryGreen
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 4),

        // Swiggy/Zomato Inline Control
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: quantity == 0
              ? _buildAddButton(key: const ValueKey('add_btn'))
              : _buildQuantityStepper(
                  key: const ValueKey('stepper_ctrl'),
                  qty: quantity,
                ),
        ),
      ],
    );
  }

  /// Default State: Small "+" Add Button
  Widget _buildAddButton({required Key key}) {
    return Material(
      key: key,
      color: AppColors.primaryGreen,
      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.radiusSmall),
        onTap: onAdd,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                'Add',
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Active State: Compact `[ − ] 1 [ + ]` Quantity Stepper
  Widget _buildQuantityStepper({required Key key, required int qty}) {
    return Container(
      key: key,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppColors.radiusSmall),
        border: Border.all(color: AppColors.secondaryGreen, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrement button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(AppColors.radiusSmall - 1),
              ),
              onTap: onDecrement,
              child: Container(
                width: 32,
                height: 34,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.remove_rounded,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),

          // Quantity indicator
          Container(
            constraints: const BoxConstraints(minWidth: 26),
            alignment: Alignment.center,
            child: Text(
              '$qty',
              style: AppTextStyles.labelMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
          ),

          // Increment button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.horizontal(
                right: Radius.circular(AppColors.radiusSmall - 1),
              ),
              onTap: onAdd,
              child: Container(
                width: 32,
                height: 34,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.add_rounded,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BOTTOM BAR: PERSISTENT DOCKED SUMMARY — Liquid glass style
// =============================================================================

class _OrderBottomBar extends StatelessWidget {
  final int totalCount;
  final int parcelCount;
  final double totalPrice;
  final bool canSubmit;
  final bool isEditing;
  final VoidCallback onReview;

  const _OrderBottomBar({
    required this.totalCount,
    this.parcelCount = 0,
    required this.totalPrice,
    required this.canSubmit,
    this.isEditing = false,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    String countLabel = totalCount == 1 ? '1 item' : '$totalCount items';
    if (parcelCount > 0) {
      if (parcelCount == totalCount) {
        countLabel = '$countLabel (📦 All Parcel)';
      } else {
        countLabel = '$countLabel (📦 $parcelCount parcel)';
      }
    }

    final isCompact = Responsive.isCompact(context);

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: const Border(
          top: BorderSide(color: AppColors.borderLight, width: 1),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 10,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Summary Details (Items + Total)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  totalCount > 0 ? countLabel : 'Cart is empty',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: parcelCount > 0 ? FontWeight.w600 : FontWeight.normal,
                    fontSize: isCompact ? 11 : 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '₹${totalPrice.toStringAsFixed(2)}',
                  style: AppTextStyles.moneyLarge.copyWith(
                    color: AppColors.primaryDark,
                    fontSize: isCompact ? 16 : 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Action Button ("Update order" if editing, otherwise "Review order")
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  canSubmit ? AppColors.primaryGreen : AppColors.borderStrong,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 14 : 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radiusSmall),
              ),
            ),
            onPressed: canSubmit ? onReview : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEditing ? 'Update order' : 'Review order',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: isCompact ? 12 : 14,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  isEditing
                      ? Icons.check_circle_outline_rounded
                      : Icons.arrow_forward_rounded,
                  size: isCompact ? 14 : 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TABLET LANDSCAPE: LIVE CART SUMMARY PANEL (Right Pane)
// =============================================================================

class _TabletCartSummaryPanel extends ConsumerWidget {
  final VoidCallback onReview;

  const _TabletCartSummaryPanel({required this.onReview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderState = ref.watch(serverOrderProvider);
    final cartItems = orderState.cart.values.toList();
    final customer = orderState.selectedCustomer;
    final table = orderState.activeTable;
    final totalCount = orderState.totalItemsCount;
    final grandTotal = orderState.grandTotalAmount;
    final canSubmit = orderState.canSubmitOrder;
    final isEditing = orderState.isEditingOrder;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.creamSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Header: Table & Customer Context (Mockup Screen 3) ────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F2E1E),
              border: Border(
                bottom: BorderSide(color: Color(0xFF265036), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF266540),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.table_restaurant_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing
                            ? 'Editing #${orderState.editingOrderNumber ?? ""}'
                            : (table?.tableNumber.startsWith('T') ?? false)
                                ? 'Table ${table?.tableNumber}'
                                : 'Table ${table?.tableNumber ?? ""}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        customer?.displayName ?? "Customer",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7CB342),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (totalCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF266540),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$totalCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ─── Cart Items List / Empty Placeholder ────────────
          Expanded(
            child: cartItems.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryLight.withValues(alpha: 0.6),
                              border: Border.all(
                                color: AppColors.primaryGreen.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.local_cafe_outlined,
                              size: 28,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No items added yet',
                            style: AppTextStyles.h4.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap [+ Add] on any menu card to build this order',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    itemCount: cartItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final cartItem = cartItems[index];
                      final item = cartItem.menuItem;
                      final hasAddons = cartItem.selectedAddons.isNotEmpty;

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                          border: Border.all(color: AppColors.borderLight),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x06000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: AppTextStyles.bodyMedium.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '₹${cartItem.itemTotal.toStringAsFixed(2)}',
                                        style: AppTextStyles.moneySmall.copyWith(
                                          color: AppColors.primaryDark,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Parcel toggle pill
                                InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    ref
                                        .read(serverOrderProvider.notifier)
                                        .toggleItemParcel(item.id);
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: cartItem.isParcel
                                          ? const Color(0xFFFFF7ED)
                                          : AppColors.warmSurface,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: cartItem.isParcel
                                            ? const Color(0xFFFED7AA)
                                            : AppColors.borderLight,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          cartItem.isParcel
                                              ? Icons.takeout_dining_rounded
                                              : Icons.restaurant_rounded,
                                          size: 11,
                                          color: cartItem.isParcel
                                              ? const Color(0xFFEA580C)
                                              : AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          cartItem.isParcel ? 'Parcel' : 'Dine',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: cartItem.isParcel
                                                ? const Color(0xFFEA580C)
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Selected Addons summary
                            if (hasAddons) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                children: cartItem.selectedAddons.map((addon) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '+${addon.name}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],

                            const SizedBox(height: 6),

                            // Stepper and customize action
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                InkWell(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    ItemCustomizationModal.show(
                                      context: context,
                                      item: item,
                                      initialCartItem: cartItem,
                                      availableAddons:
                                          orderState.availableAddons,
                                      onSave: (configuredItem) {
                                        ref
                                            .read(serverOrderProvider.notifier)
                                            .setConfiguredItem(configuredItem);
                                      },
                                    );
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      'Edit addons ›',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryGreen,
                                      ),
                                    ),
                                  ),
                                ),

                                // Stepper [-] qty [+]
                                Container(
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondaryLight,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.secondaryGreen,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          ref
                                              .read(serverOrderProvider.notifier)
                                              .decrementItem(item.id);
                                        },
                                        child: const SizedBox(
                                          width: 26,
                                          height: 28,
                                          child: Icon(
                                            Icons.remove_rounded,
                                            size: 14,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        constraints:
                                            const BoxConstraints(minWidth: 22),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${cartItem.quantity}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          ref
                                              .read(serverOrderProvider.notifier)
                                              .addItem(item);
                                        },
                                        child: const SizedBox(
                                          width: 26,
                                          height: 28,
                                          child: Icon(
                                            Icons.add_rounded,
                                            size: 14,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // ─── Financial Summary & Review Action ───────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppColors.borderLight, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0C000000),
                  blurRadius: 8,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total ($totalCount ${totalCount == 1 ? "item" : "items"})',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '₹${grandTotal.toStringAsFixed(2)}',
                      style: AppTextStyles.moneyLarge.copyWith(
                        color: AppColors.primaryDark,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: canSubmit ? onReview : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF266540),
                      disabledBackgroundColor: AppColors.borderMedium,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: const Color(0xFF266540).withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isEditing
                              ? Icons.save_rounded
                              : Icons.check_circle_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isEditing ? 'Save Changes' : 'Finish Customer',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
