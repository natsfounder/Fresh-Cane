import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/subscription_service.dart';
import '../../state/cashier_provider.dart';
import '../../state/cashier_state.dart';
import '../common/exit_confirmation_dialog.dart';
import '../common/user_profile_badge.dart';
import 'views/cashier_expenses_view.dart';
import 'views/cashier_today_bills_sheet.dart';
import 'views/dine_in_billing_view.dart';
import 'views/parcel_ordering_view.dart';
import 'widgets/cashier_drawer.dart';

/// Complete Operational Landing Screen for Cashier Terminal.
///
/// Layout:
/// - Mobile/Compact (width < 768): Bottom navigation bar with 3 tabs.
/// - Tablet/Wide (width >= 768): Top AppBar segmented tab switcher.
///
/// The 3 tabs are completely independent:
///   0 → Dine-In Billing Queue
///   1 → Parcel / Takeaway Ordering
///   2 → Expense Recording Desk
///
/// A bill-history icon in the AppBar opens today's settled bills summary.
class CashierHomeScreen extends ConsumerWidget {
  const CashierHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Guard: Listen for software freeze to redirect to warning screen
    ref.listen<bool>(softwareFrozenProvider, (prev, isFrozen) {
      if (isFrozen && context.mounted) {
        Navigator.of(context).pushReplacementNamed('/software-frozen');
      }
    });

    final cashierState = ref.watch(cashierProvider);
    final notifier = ref.read(cashierProvider.notifier);
    final mode = cashierState.activeMode;
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 768;

    int bottomNavIndex = 0;
    if (mode == CashierMode.parcel) bottomNavIndex = 1;
    if (mode == CashierMode.expenses) bottomNavIndex = 2;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await ExitConfirmationDialog.show(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
      drawer: const CashierDrawer(),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.forestHeaderGradient,
          ),
        ),
        elevation: 0,
        titleSpacing: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
            tooltip: 'Menu',
            onPressed: () {
              HapticFeedback.lightImpact();
              Scaffold.of(ctx).openDrawer();
            },
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.secondaryGreen,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.secondaryGreen.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              if (!isCompact)
                Text(
                  'Fresh Cane Cashier',
                  style: AppTextStyles.h3.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (isCompact)
                Flexible(
                  child: Text(
                    _modeLabel(mode),
                    style: AppTextStyles.h3.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          // ─── Tablet/Wide: in-AppBar 3-way mode switcher ────────────────
          if (!isCompact) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tabBtn(label: '🍽  Dine-In', isSelected: mode == CashierMode.dineIn || mode == CashierMode.none, onTap: () => notifier.selectMode(CashierMode.dineIn)),
                  _tabBtn(label: '🥡  Parcel', isSelected: mode == CashierMode.parcel, onTap: () => notifier.selectMode(CashierMode.parcel)),
                  _tabBtn(label: '💰  Expenses', isSelected: mode == CashierMode.expenses, onTap: () => notifier.selectMode(CashierMode.expenses)),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],

          // ─── Bill History icon (all layouts) ───────────────────────────
          IconButton(
            icon: const Icon(Icons.receipt_outlined, color: Colors.white, size: 22),
            tooltip: "Today's Bills",
            onPressed: () => CashierTodayBillsSheet.show(context),
          ),

          const Center(child: UserProfileBadge(isDarkText: false)),
          const SizedBox(width: 8),
        ],
      ),

      // ─── Mobile: Bottom Navigation ─────────────────────────────────────
      bottomNavigationBar: isCompact
          ? Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: AppColors.borderLight, width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0C000000),
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: bottomNavIndex,
                selectedItemColor: AppColors.primaryGreen,
                unselectedItemColor: AppColors.textSecondary,
                backgroundColor: Colors.white,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
                onTap: (i) {
                  if (i == 0) notifier.selectMode(CashierMode.dineIn);
                  if (i == 1) notifier.selectMode(CashierMode.parcel);
                  if (i == 2) notifier.selectMode(CashierMode.expenses);
                },
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.table_restaurant_rounded), label: 'Dine-In'),
                  BottomNavigationBarItem(icon: Icon(Icons.takeout_dining_rounded), label: 'Parcel'),
                  BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Expenses'),
                ],
              ),
            )
          : null,

      body: _buildCurrentView(mode),
      ),
    );
  }

  String _modeLabel(CashierMode mode) {
    switch (mode) {
      case CashierMode.parcel: return 'Parcel / Takeaway';
      case CashierMode.expenses: return 'Expense Desk';
      default: return 'Dine-In Billing';
    }
  }

  Widget _tabBtn({required String label, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.3),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentView(CashierMode mode) {
    switch (mode) {
      case CashierMode.parcel:   return const ParcelOrderingView();
      case CashierMode.expenses: return const CashierExpensesView();
      case CashierMode.dineIn:
      default:                   return const DineInBillingView();
    }
  }
}
