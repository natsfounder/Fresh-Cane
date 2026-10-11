import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/expense_model.dart';
import '../../../state/cashier_expense_provider.dart';
import '../../../state/payment_method_provider.dart';

/// POS / Order-Taking Style Expense Management Desk for Cashier.
///
/// Workflow:
/// - Screen looks and functions like the Order Taking Screen.
/// - Admin-defined expenses appear as visual Category Cards / Item Tiles.
/// - 1-Tap on any tile opens a quick amount keypad to record immediately.
/// - Dedicated "+ Custom Expense" card to record ad-hoc/unexpected expenses.
/// - Live Month Ledger panel (like the Cart/Bill) displays all recorded expenses with totals.
/// - Full Edit (✏️) and Delete (🗑️) options with audit trail.
/// - Responsive for Mobile & Tablet (portrait & landscape).
class CashierExpensesView extends ConsumerStatefulWidget {
  const CashierExpensesView({super.key});

  @override
  ConsumerState<CashierExpensesView> createState() => _CashierExpensesViewState();
}

class _CashierExpensesViewState extends ConsumerState<CashierExpensesView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _mobileTab = 0; // 0: Grid of Expenses, 1: Month Ledger

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cashierExpenseProvider);
    final notifier = ref.read(cashierExpenseProvider.notifier);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 720;

    // Toast feedback listeners
    ref.listen<String?>(cashierExpenseProvider.select((s) => s.errorMessage), (prev, next) {
      if (next != null && next.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
        notifier.clearNotifications();
      }
    });

    ref.listen<String?>(cashierExpenseProvider.select((s) => s.successMessage), (prev, next) {
      if (next != null && next.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: AppColors.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
        notifier.clearNotifications();
      }
    });

    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    final monthLabel = state.monthLabel.isNotEmpty
        ? state.monthLabel
        : DateFormat('MMMM yyyy').format(state.targetDate);

    // Filter definitions by search
    final filteredDefinitions = state.fixedDefinitions.where((d) {
      if (_searchQuery.isEmpty) return true;
      return d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (d.description ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      body: isWide
          ? _buildSplitScreen(context, monthLabel, filteredDefinitions, state, notifier)
          : _buildMobileScreen(context, monthLabel, filteredDefinitions, state, notifier),
    );
  }

  // ===========================================================================
  // 1. TABLET / LANDSCAPE: SPLIT SCREEN (POS ORDER TAKING STYLE)
  // ===========================================================================

  Widget _buildSplitScreen(
    BuildContext context,
    String monthLabel,
    List<ExpenseDefinition> definitions,
    CashierExpenseState state,
    CashierExpenseNotifier notifier,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LEFT 60%: Expense Category Tiles Grid
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSearchAndFilterHeader(definitions.length),
              Expanded(
                child: _buildExpenseTilesGrid(context, definitions, notifier),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8E5)),

        // RIGHT 40%: This Month's Recorded Expenses (Cart / Bill style)
        Expanded(
          flex: 4,
          child: Container(
            color: Colors.white,
            child: _buildMonthLedgerPanel(context, monthLabel, state, notifier, isWide: true),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. MOBILE PORTRAIT: TWO-TAB POS SCREEN WITH LIVE BOTTOM BAR
  // ===========================================================================

  Widget _buildMobileScreen(
    BuildContext context,
    String monthLabel,
    List<ExpenseDefinition> definitions,
    CashierExpenseState state,
    CashierExpenseNotifier notifier,
  ) {
    return Column(
      children: [
        // Mobile Segmented Switch
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            height: 42,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    title: 'Expense Categories',
                    icon: Icons.grid_view_rounded,
                    index: 0,
                  ),
                ),
                Expanded(
                  child: _buildTabButton(
                    title: 'Month Ledger (${state.expenses.length})',
                    icon: Icons.receipt_long_rounded,
                    index: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8E5)),

        // Tab Content
        Expanded(
          child: _mobileTab == 0
              ? Column(
                  children: [
                    _buildSearchAndFilterHeader(definitions.length),
                    Expanded(
                      child: _buildExpenseTilesGrid(context, definitions, notifier),
                    ),
                  ],
                )
              : _buildMonthLedgerPanel(context, monthLabel, state, notifier, isWide: false),
        ),

        // Running Bottom Total Bar (on Grid View)
        if (_mobileTab == 0)
          _buildMobileBottomTotalBar(context, monthLabel, state),
      ],
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required int index,
  }) {
    final isSelected = _mobileTab == index;
    return InkWell(
      onTap: () => setState(() => _mobileTab = index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF266540) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. EXPENSE CATEGORY TILES (LIKE MENU ITEMS IN ORDER TAKING)
  // ===========================================================================

  Widget _buildSearchAndFilterHeader(int count) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F5F4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search expense category (Rent, EB Bill, etc.)...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count categories',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseTilesGrid(
    BuildContext context,
    List<ExpenseDefinition> definitions,
    CashierExpenseNotifier notifier,
  ) {
    if (definitions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No Expense Categories Configured',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              'Only Admin has credentials to configure expense categories.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800
            ? 4
            : constraints.maxWidth > 520
                ? 3
                : 2;

        return GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.95,
          ),
          itemCount: definitions.length,
          itemBuilder: (context, index) {
            final item = definitions[index];
            return _buildCategoryItemCard(context, item, notifier);
          },
        );
      },
    );
  }

  /// Individual Expense Category Card (like a dish/drink card in order taking)
  Widget _buildCategoryItemCard(
    BuildContext context,
    ExpenseDefinition item,
    CashierExpenseNotifier notifier,
  ) {
    final iconData = _getIconForExpense(item.name);
    final color = _getColorForExpense(item.name);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openRecordAmountModal(context, item, notifier),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Icon circle + frequency badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconData, size: 20, color: color),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.frequencyLabel,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),

              // Title and Description
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.hasSubExpenses) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${item.defaultSubExpenses.length} items: ${item.defaultSubExpenses.take(2).join(', ')}${item.defaultSubExpenses.length > 2 ? '...' : ''}',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else if (item.displayDescription.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.displayDescription,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),

              // Quick "Tap to Record" Action button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F8F4),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.hasSubExpenses ? Icons.playlist_add_check_rounded : Icons.payments_outlined,
                      size: 14,
                      color: const Color(0xFF2D6A4F),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.hasSubExpenses ? 'Itemize (₹)' : 'Record ₹',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D6A4F),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. THIS MONTH'S RECORDED EXPENSES (CART / BILL PANEL STYLE)
  // ===========================================================================

  Widget _buildMonthLedgerPanel(
    BuildContext context,
    String monthLabel,
    CashierExpenseState state,
    CashierExpenseNotifier notifier, {
    required bool isWide,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Total Spent Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF0F2E1E),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    monthLabel.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.secondaryLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1.1,
                    ),
                  ),
                  InkWell(
                    onTap: () => notifier.loadExpenses(),
                    child: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '₹${state.totalExpenses.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Total Spent (${state.expenses.length} bills)',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Scrollable List of Recorded Expenses
        Expanded(
          child: state.expenses.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        const Text(
                          'No expenses recorded yet',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap any category tile on the left to record.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: state.expenses.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final exp = state.expenses[i];
                    return _buildLedgerLineItem(context, exp, notifier);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLedgerLineItem(
    BuildContext context,
    ExpenseTransaction exp,
    CashierExpenseNotifier notifier,
  ) {
    final timeStr = DateFormat('hh:mm a').format(exp.createdAt);
    final dateStr = DateFormat('dd MMM').format(exp.expenseDate);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circular Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8F4),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_rounded, size: 18, color: Color(0xFF2D6A4F)),
          ),
          const SizedBox(width: 10),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exp.expenseName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateStr, $timeStr • ${exp.paymentMethodLabel} • by ${exp.recordedByName}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (exp.hasSubExpenses) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F8F4),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFD8F3DC)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.list_alt_rounded, size: 12, color: Color(0xFF2D6A4F)),
                            const SizedBox(width: 4),
                            Text(
                              '${exp.subExpenses.length} Sub-expenses:',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        ...exp.subExpenses.map(
                          (sub) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('• ${sub.name}', style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
                                Text('₹${sub.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1B4332))),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (exp.displayNotes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    exp.displayNotes,
                    style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (exp.isEdited) ...[
                  const SizedBox(height: 2),
                  Text(
                    '⚠️ Edited on ${exp.editedAt != null ? DateFormat('dd MMM, hh:mm a').format(exp.editedAt!) : 'recently'}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Amount
          Text(
            '₹${exp.amount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
          ),

          // Action Menu (Edit / Delete)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, size: 18, color: Colors.grey.shade600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (val) {
              if (val == 'edit') {
                _openEditModal(context, exp, notifier);
              } else if (val == 'delete') {
                _openDeleteDialog(context, exp, notifier);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: AppColors.textPrimary),
                    SizedBox(width: 8),
                    Text('Edit', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomTotalBar(
    BuildContext context,
    String monthLabel,
    CashierExpenseState state,
  ) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TOTAL THIS MONTH',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                ),
                Text(
                  '₹${state.totalExpenses.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => setState(() => _mobileTab = 1),
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              label: Text('View Bills (${state.expenses.length})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 5. RECORD AMOUNT MODAL (FAST 1-TAP ENTRY FOR ADMIN CATEGORY)
  // ===========================================================================

  void _openRecordAmountModal(
    BuildContext context,
    ExpenseDefinition item,
    CashierExpenseNotifier notifier,
  ) {
    HapticFeedback.lightImpact();
    final notesCtrl = TextEditingController();
    String method = 'cash';
    final formKey = GlobalKey<FormState>();

    // For single amount:
    final singleAmountCtrl = TextEditingController();

    // For sub-expenses: Map of item name -> amount controller
    final Map<String, TextEditingController> subCtrls = {
      for (final s in item.defaultSubExpenses) s: TextEditingController(),
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (mCtx) => StatefulBuilder(
        builder: (ctx, setMS) {
          final now = DateTime.now();
          final formattedTime = DateFormat('dd MMM yyyy, hh:mm a').format(now);

          return _modalSheetContainer(
            mCtx: mCtx,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _modalHandle(),
                  const SizedBox(height: 14),

                  // Header with Category name & icon
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE8F5E9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_getIconForExpense(item.name), color: const Color(0xFF2D6A4F), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            Text(
                              item.hasSubExpenses
                                  ? 'Enter amounts for items purchased'
                                  : 'Category: ${item.frequencyLabel}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                        onPressed: () => Navigator.pop(mCtx),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // SCENARIO A: EXPENSE HAS SUB-EXPENSES (e.g. Fruit -> Apple, Banana, Watermelon)
                  if (item.hasSubExpenses) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F8F4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF2D6A4F)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Enter amount for each item purchased (leave 0 or blank if not bought)',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // List of Admin-defined sub-expenses with read-only item names
                    ...item.defaultSubExpenses.map((subName) {
                      final ctrl = subCtrls[subName]!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Row(
                          children: [
                            // Read-only Item Name Badge (Admin controlled)
                            Expanded(
                              flex: 5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.label_outline_rounded, size: 16, color: Color(0xFF2D6A4F)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        subName,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Cashier enters ONLY the amount
                            Expanded(
                              flex: 4,
                              child: TextFormField(
                                controller: ctrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 16, color: AppColors.primaryGreen),
                                  hintText: '0.00',
                                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                ),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                                onChanged: (_) => setMS(() {}),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 4),

                    // Running Total Summary Card
                    Builder(
                      builder: (_) {
                        double total = 0;
                        int count = 0;
                        for (final entry in subCtrls.entries) {
                          final a = double.tryParse(entry.value.text.trim()) ?? 0;
                          if (a > 0) {
                            total += a;
                            count++;
                          }
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFC8E6C9)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'TOTAL ($count item${count == 1 ? '' : 's'}):',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
                              ),
                              Text(
                                '₹${total.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ]

                  // SCENARIO B: FLAT EXPENSE (No Sub-Expenses, e.g. Rent, EB Bill)
                  else ...[
                    const Text('ENTER EXPENSE AMOUNT (₹) *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: singleAmountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      autofocus: true,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.currency_rupee_rounded, color: AppColors.primaryGreen, size: 24),
                        hintText: '0.00',
                        hintStyle: TextStyle(color: Colors.grey.shade300),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter amount';
                        final val = double.tryParse(v.trim());
                        if (val == null || val <= 0) return 'Must be greater than 0';
                        return null;
                      },
                    ),
                  ],

                  const SizedBox(height: 16),
                  _buildPaymentPills(method, (m) => setMS(() => method = m)),
                  const SizedBox(height: 14),

                  // Optional Notes
                  TextFormField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      hintText: 'Optional note (e.g. vendor name, receipt no)',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        'Auto-timestamp: $formattedTime',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final note = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();

                        if (item.hasSubExpenses) {
                          // Collect only items that have an entered amount > 0
                          final List<SubExpenseItem> recordedSubExpenses = [];
                          double totalAmt = 0;
                          for (final entry in subCtrls.entries) {
                            final a = double.tryParse(entry.value.text.trim()) ?? 0;
                            if (a > 0) {
                              recordedSubExpenses.add(SubExpenseItem(name: entry.key, amount: a));
                              totalAmt += a;
                            }
                          }

                          if (recordedSubExpenses.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter an amount for at least one item')),
                            );
                            return;
                          }

                          Navigator.pop(mCtx);
                          await notifier.submitFixedExpense(
                            definitionId: item.id,
                            amount: totalAmt,
                            paymentMethod: method,
                            notes: note,
                            subExpenses: recordedSubExpenses,
                          );
                        } else {
                          if (!formKey.currentState!.validate()) return;
                          final amt = double.parse(singleAmountCtrl.text.trim());
                          Navigator.pop(mCtx);
                          await notifier.submitFixedExpense(
                            definitionId: item.id,
                            amount: amt,
                            paymentMethod: method,
                            notes: note,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B4332),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Record Expense', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 6. EDIT & DELETE DIALOGS
  // ===========================================================================

  void _openEditModal(
    BuildContext context,
    ExpenseTransaction item,
    CashierExpenseNotifier notifier,
  ) {
    HapticFeedback.lightImpact();
    final notesCtrl = TextEditingController(text: item.displayNotes);
    final reasonCtrl = TextEditingController();
    String method = item.paymentMethod;
    final formKey = GlobalKey<FormState>();

    final singleAmountCtrl = TextEditingController(text: item.amount.toStringAsFixed(2));

    // Map of item name -> controller for sub-expenses
    final Map<String, TextEditingController> subCtrls = {
      if (item.hasSubExpenses)
        for (final s in item.subExpenses)
          s.name: TextEditingController(
            text: s.amount > 0 ? (s.amount % 1 == 0 ? s.amount.toInt().toString() : s.amount.toStringAsFixed(2)) : '',
          ),
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (mCtx) => StatefulBuilder(
        builder: (ctx, setMS) {
          return _modalSheetContainer(
            mCtx: mCtx,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _modalHandle(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Edit ${item.expenseName}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                        onPressed: () => Navigator.pop(mCtx),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (item.hasSubExpenses) ...[
                    const Text(
                      'SUB-EXPENSES AMOUNTS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    ...subCtrls.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 4,
                              child: TextFormField(
                                controller: entry.value,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 16, color: AppColors.primaryGreen),
                                  hintText: '0.00',
                                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                ),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                                onChanged: (_) => setMS(() {}),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    Builder(
                      builder: (_) {
                        double total = 0;
                        int count = 0;
                        for (final entry in subCtrls.entries) {
                          final a = double.tryParse(entry.value.text.trim()) ?? 0;
                          if (a > 0) {
                            total += a;
                            count++;
                          }
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFC8E6C9)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'TOTAL ($count item${count == 1 ? '' : 's'}):',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
                              ),
                              Text(
                                '₹${total.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ] else ...[
                    const Text('AMOUNT (₹) *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: singleAmountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      autofocus: true,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.currency_rupee_rounded, color: AppColors.primaryGreen),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter amount';
                        final val = double.tryParse(v.trim());
                        if (val == null || val <= 0) return 'Must be greater than 0';
                        return null;
                      },
                    ),
                  ],

                  const SizedBox(height: 16),
                  _buildPaymentPills(method, (m) => setMS(() => method = m)),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                      hintText: 'Reason for edit (optional)',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      hintText: 'Notes',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final note = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
                        final reason = reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim();

                        if (item.hasSubExpenses) {
                          final List<SubExpenseItem> updatedSubs = [];
                          double totalAmt = 0;
                          for (final entry in subCtrls.entries) {
                            final a = double.tryParse(entry.value.text.trim()) ?? 0;
                            if (a > 0) {
                              updatedSubs.add(SubExpenseItem(name: entry.key, amount: a));
                              totalAmt += a;
                            }
                          }
                          if (updatedSubs.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter an amount for at least one item')),
                            );
                            return;
                          }

                          Navigator.pop(mCtx);
                          await notifier.editExpense(
                            transactionId: item.id,
                            amount: totalAmt,
                            paymentMethod: method,
                            notes: note,
                            editReason: reason,
                            subExpenses: updatedSubs,
                          );
                        } else {
                          if (!formKey.currentState!.validate()) return;
                          final amt = double.parse(singleAmountCtrl.text.trim());
                          Navigator.pop(mCtx);
                          await notifier.editExpense(
                            transactionId: item.id,
                            amount: amt,
                            paymentMethod: method,
                            notes: note,
                            editReason: reason,
                            subExpenses: null,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B4332),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Update Expense', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openDeleteDialog(
    BuildContext context,
    ExpenseTransaction item,
    CashierExpenseNotifier notifier,
  ) {
    HapticFeedback.mediumImpact();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 22),
            SizedBox(width: 8),
            Text('Delete Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remove "${item.expenseName}" (₹${item.amount.toStringAsFixed(2)})?'),
            const SizedBox(height: 8),
            Text(
              'This record will be removed from monthly totals and archived for admin reports.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                hintText: 'Reason for deletion (optional)',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dlgCtx);
              await notifier.deleteExpense(
                transactionId: item.id,
                deleteReason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 8. HELPERS & CATEGORY ICONS
  // ===========================================================================

  Widget _buildPaymentPills(String selected, void Function(String) onSelect) {
    final enabledMethods = ref.watch(enabledPaymentMethodsProvider);

    return Row(
      children: enabledMethods.map((m) {
        final isSel = selected == m.id;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => onSelect(m.id),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSel ? const Color(0xFF1B4332) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(m.icon, size: 16, color: isSel ? Colors.white : Colors.grey.shade700),
                    const SizedBox(height: 2),
                    Text(
                      m.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                        color: isSel ? Colors.white : Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _modalSheetContainer({required BuildContext mCtx, required Widget child}) {
    final keyboardH = MediaQuery.of(mCtx).viewInsets.bottom;
    final screenH = MediaQuery.of(mCtx).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: screenH * 0.90),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: 14, left: 20, right: 20, bottom: keyboardH + 20),
          child: child,
        ),
      ),
    );
  }

  Widget _modalHandle() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }

  IconData _getIconForExpense(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('rent')) return Icons.storefront_rounded;
    if (lower.contains('eb') || lower.contains('elect') || lower.contains('power')) return Icons.bolt_rounded;
    if (lower.contains('salary') || lower.contains('staff') || lower.contains('wage')) return Icons.badge_outlined;
    if (lower.contains('cane') || lower.contains('sugar')) return Icons.agriculture_rounded;
    if (lower.contains('lemon') || lower.contains('fruit')) return Icons.eco_rounded;
    if (lower.contains('ice')) return Icons.ac_unit_rounded;
    if (lower.contains('amc') || lower.contains('repair') || lower.contains('service')) return Icons.build_rounded;
    if (lower.contains('clean') || lower.contains('wash')) return Icons.cleaning_services_rounded;
    if (lower.contains('cup') || lower.contains('straw') || lower.contains('pack')) return Icons.inventory_2_outlined;
    return Icons.receipt_long_rounded;
  }

  Color _getColorForExpense(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('rent')) return const Color(0xFF2E7D32);
    if (lower.contains('eb') || lower.contains('elect') || lower.contains('power')) return const Color(0xFFF57F17);
    if (lower.contains('salary') || lower.contains('staff')) return const Color(0xFF1565C0);
    if (lower.contains('cane') || lower.contains('sugar')) return const Color(0xFF388E3C);
    if (lower.contains('lemon') || lower.contains('fruit')) return const Color(0xFFAFB42B);
    if (lower.contains('ice')) return const Color(0xFF0097A7);
    if (lower.contains('amc') || lower.contains('repair')) return const Color(0xFFD84315);
    return const Color(0xFF4527A0);
  }
}

