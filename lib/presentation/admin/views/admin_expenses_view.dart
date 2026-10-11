import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/expense_model.dart';
import '../../../state/admin_provider.dart';
import '../../../state/admin_state.dart';

/// Complete Admin View for Expense Management & Reporting.
/// Aligned with the Cashier POS Order-Taking screen:
/// 1. Expense Categories (Categories created by Admin that appear as 1-tap tiles in the Cashier POS screen)
/// 2. Expense Reports (Financial transactions recorded by Cashier with KPIs, category filters, and direct Downloads for Excel & PDF)
class AdminExpensesView extends ConsumerStatefulWidget {
  const AdminExpensesView({super.key});

  @override
  ConsumerState<AdminExpensesView> createState() => _AdminExpensesViewState();
}

class _AdminExpensesViewState extends ConsumerState<AdminExpensesView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('rent')) return Icons.storefront_rounded;
    if (lower.contains('electricity') || lower.contains('eb') || lower.contains('current') || lower.contains('power')) {
      return Icons.electric_bolt_rounded;
    }
    if (lower.contains('salary') || lower.contains('wages') || lower.contains('staff')) {
      return Icons.badge_rounded;
    }
    if (lower.contains('cane') || lower.contains('sugar') || lower.contains('supply')) {
      return Icons.grass_rounded;
    }
    if (lower.contains('lemon') || lower.contains('fruit') || lower.contains('mint') || lower.contains('ginger')) {
      return Icons.eco_rounded;
    }
    if (lower.contains('ice')) return Icons.ac_unit_rounded;
    if (lower.contains('maintenance') || lower.contains('repair') || lower.contains('service')) {
      return Icons.handyman_rounded;
    }
    if (lower.contains('clean') || lower.contains('wash') || lower.contains('waste')) {
      return Icons.cleaning_services_rounded;
    }
    if (lower.contains('tea') || lower.contains('coffee') || lower.contains('snack')) {
      return Icons.local_cafe_rounded;
    }
    if (lower.contains('wifi') || lower.contains('internet') || lower.contains('phone')) {
      return Icons.wifi_rounded;
    }
    if (lower.contains('pack') || lower.contains('cup') || lower.contains('straw')) {
      return Icons.inventory_2_rounded;
    }
    return Icons.category_rounded;
  }

  Color _getCategoryColor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('rent')) return const Color(0xFF2D6A4F);
    if (lower.contains('electricity') || lower.contains('eb') || lower.contains('power')) {
      return const Color(0xFFD97706);
    }
    if (lower.contains('salary') || lower.contains('staff')) return const Color(0xFF4338CA);
    if (lower.contains('cane') || lower.contains('sugar')) return const Color(0xFF15803D);
    if (lower.contains('lemon') || lower.contains('fruit')) return const Color(0xFFEAB308);
    if (lower.contains('ice')) return const Color(0xFF0284C7);
    if (lower.contains('maintenance') || lower.contains('repair')) return const Color(0xFFEA580C);
    if (lower.contains('clean')) return const Color(0xFF0D9488);
    return const Color(0xFF2563EB);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);

    // Toast listener for download confirmations & errors
    ref.listen<String?>(adminProvider.select((s) => s.successMessage), (prev, next) {
      if (next != null && next.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(next, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
            backgroundColor: AppColors.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });

    ref.listen<String?>(adminProvider.select((s) => s.errorMessage), (prev, next) {
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
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          // Sub-navigation tab bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey.shade700,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: const [
                        Tab(text: 'Expense Categories'),
                        Tab(text: 'Expense Reports'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCategoriesTab(context, state, notifier),
                _buildReportsTab(context, state, notifier),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SUB-SECTION 1: EXPENSE CATEGORIES (FOR CASHIER POS TILES)
  // ===========================================================================

  Widget _buildCategoriesTab(BuildContext context, AdminState state, AdminNotifier notifier) {
    final defs = state.expenseDefinitions.where((d) {
      if (_searchQuery.isEmpty) return true;
      return d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (d.description ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // Controls Row: Search + Add Category Button
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search expense categories...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => _openCategoryDialog(context, null, notifier),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Category'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${defs.length} categories configured (${defs.where((d) => d.isActive).length} active in Cashier POS screen)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Categories list
        Expanded(
          child: state.isLoadingExpenses
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
              : defs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.category_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            'No expense categories found.',
                            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Categories added here appear directly as tiles on the Cashier Expense screen.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: defs.length,
                      itemBuilder: (context, index) {
                        final item = defs[index];
                        return _buildCategoryCard(context, item, notifier);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(BuildContext context, ExpenseDefinition item, AdminNotifier notifier) {
    final catColor = _getCategoryColor(item.name);
    final catIcon = _getCategoryIcon(item.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isActive ? Colors.grey.shade200 : Colors.red.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Visual Icon Badge matching Cashier tiles
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(catIcon, color: catColor, size: 22),
          ),
          const SizedBox(width: 14),

          // Category Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: item.isActive ? AppColors.textPrimary : Colors.grey,
                          decoration: item.isActive ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.isActive ? const Color(0xFFD8F3DC) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.isActive ? 'Cashier Tile: Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: item.isActive ? const Color(0xFF2D6A4F) : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.displayDescription.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.displayDescription,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (item.hasSubExpenses) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F8F4),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFB7E4C7)),
                        ),
                        child: Text(
                          '${item.defaultSubExpenses.length} items:',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
                        ),
                      ),
                      ...item.defaultSubExpenses.map(
                        (sub) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            sub,
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Actions: Edit and Active toggle switch
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                    tooltip: 'Edit Category',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(6),
                    onPressed: () => _openCategoryDialog(context, item, notifier),
                  ),
                  const SizedBox(width: 4),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: item.isActive,
                      activeThumbColor: AppColors.primaryGreen,
                      onChanged: (val) {
                        notifier.toggleExpenseDefinitionStatus(item.id, val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dialog for adding or editing an expense category
  void _openCategoryDialog(BuildContext context, ExpenseDefinition? existing, AdminNotifier notifier) {
    HapticFeedback.lightImpact();
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descController = TextEditingController(text: existing?.displayDescription ?? '');
    final subExpenseInputCtrl = TextEditingController();
    final List<String> subExpenses = List<String>.from(existing?.defaultSubExpenses ?? []);
    bool hasSubExpenses = existing?.hasSubExpenses ?? false;
    bool isActive = existing?.isActive ?? true;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            void addSubExpense() {
              final text = subExpenseInputCtrl.text.trim();
              if (text.isNotEmpty && !subExpenses.contains(text)) {
                setDlgState(() {
                  subExpenses.add(text);
                  subExpenseInputCtrl.clear();
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Row(
                children: [
                  Icon(
                    existing == null ? Icons.add_circle_outline_rounded : Icons.edit_rounded,
                    color: AppColors.primaryGreen,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    existing == null ? 'Add Expense Category' : 'Edit Expense Category',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width > 480 ? 460 : MediaQuery.of(context).size.width - 64,
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CATEGORY NAME *',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: nameController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Fruit, Rent, Electricity, Cleaning Supplies',
                            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Category name is required';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Admin Decision: Does this expense have sub-expenses?
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: hasSubExpenses ? const Color(0xFFF1F8F4) : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: hasSubExpenses ? const Color(0xFFB7E4C7) : Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Has Sub-Expenses Breakdown?',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      hasSubExpenses
                                          ? 'Yes — Cashier will enter amounts for each sub-item (e.g. Apple, Banana...)'
                                          : 'No — Cashier will enter a single amount (e.g. Rent, EB Bill)',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: hasSubExpenses,
                                activeThumbColor: AppColors.primaryGreen,
                                onChanged: (val) {
                                  setDlgState(() {
                                    hasSubExpenses = val;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        // If Admin decides YES, show sub-expenses builder
                        if (hasSubExpenses) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Text(
                                'SUB-EXPENSE ITEMS',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                              ),
                              const Spacer(),
                              if (subExpenses.isNotEmpty)
                                Text(
                                  '${subExpenses.length} items defined',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Add items (e.g. Apple, Banana, Watermelon). Cashier will see these and only enter amounts.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: subExpenseInputCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'Add item (e.g. Apple)',
                                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  onSubmitted: (_) => addSubExpense(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: addSubExpense,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1B4332),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                          if (subExpenses.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: subExpenses.map((sub) {
                                return Chip(
                                  label: Text(sub, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  deleteIcon: const Icon(Icons.close, size: 14),
                                  onDeleted: () {
                                    setDlgState(() {
                                      subExpenses.remove(sub);
                                    });
                                  },
                                  backgroundColor: const Color(0xFFE8F5E9),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                );
                              }).toList(),
                            ),
                          ] else ...[
                            const SizedBox(height: 6),
                            Text(
                              '* Please add at least one item (e.g. Apple, Banana)',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.orange.shade800),
                            ),
                          ],
                        ],
                        const SizedBox(height: 14),

                        const Text(
                          'DESCRIPTION / USAGE NOTES (OPTIONAL)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: descController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'e.g. Daily fruit market purchase, rental agreement notes',
                            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.all(10),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Active status toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Show on Cashier POS Desk',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  isActive ? 'Visible as an interactive tile' : 'Hidden from cashier',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                            Switch(
                              value: isActive,
                              activeThumbColor: AppColors.primaryGreen,
                              onChanged: (v) => setDlgState(() => isActive = v),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dlgCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Auto-include any pending item typed in input box
                    final pendingText = subExpenseInputCtrl.text.trim();
                    if (hasSubExpenses && pendingText.isNotEmpty && !subExpenses.contains(pendingText)) {
                      subExpenses.add(pendingText);
                      subExpenseInputCtrl.clear();
                    }

                    if (hasSubExpenses && subExpenses.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please add at least one sub-expense item or disable sub-expenses')),
                      );
                      return;
                    }

                    Navigator.pop(dlgCtx);

                    final effectiveSubExpenses = hasSubExpenses && subExpenses.isNotEmpty ? subExpenses : null;

                    if (existing == null) {
                      await notifier.createExpenseDefinition(
                        name: nameController.text.trim(),
                        description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                        expenseType: 'mandatory',
                        frequency: 'monthly',
                        startDate: DateTime.now(),
                        isActive: isActive,
                        subExpenses: effectiveSubExpenses,
                      );
                    } else {
                      await notifier.updateExpenseDefinition(
                        id: existing.id,
                        name: nameController.text.trim(),
                        description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                        expenseType: existing.expenseType,
                        frequency: existing.frequency,
                        startDate: existing.startDate,
                        isActive: isActive,
                        subExpenses: effectiveSubExpenses,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4332),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(existing == null ? 'Create Category' : 'Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // SUB-SECTION 2: EXPENSE REPORTS (TRANSACTIONS & KPIS)
  // ===========================================================================

  Widget _buildReportsTab(BuildContext context, AdminState state, AdminNotifier notifier) {
    final rawTransactions = state.expenseTransactions;
    final selectedSubCategory = state.selectedExpenseSubCategoryFilter;
    final isSubCategoryActive = selectedSubCategory != null && selectedSubCategory.isNotEmpty;

    final transactions = isSubCategoryActive
        ? rawTransactions.where((t) =>
            t.subExpenses.any((s) => s.name.trim().toLowerCase() == selectedSubCategory.trim().toLowerCase())
          ).toList()
        : rawTransactions;

    final summary = state.expenseSummary;

    double totalExpenses = 0.0;
    double deletedExpenses = 0.0;
    int activeCount = 0;
    int deletedCount = 0;

    if (isSubCategoryActive) {
      for (final t in transactions) {
        final matchingSub = t.subExpenses.where((s) => s.name.trim().toLowerCase() == selectedSubCategory.trim().toLowerCase()).firstOrNull;
        final subAmt = matchingSub?.amount ?? 0.0;
        final isDeleted = t.isDeleted || t.status == 'deleted';
        if (isDeleted) {
          deletedExpenses += subAmt;
          deletedCount++;
        } else {
          totalExpenses += subAmt;
          activeCount++;
        }
      }
    } else {
      totalExpenses = (summary?['total_active_amount'] ?? summary?['total_expenses'] as num?)?.toDouble() ?? 0.0;
      deletedExpenses = (summary?['total_deleted_amount'] as num?)?.toDouble() ?? 0.0;
      activeCount = (summary?['total_active_count'] ?? summary?['transactions_count'] ?? transactions.where((t) => !t.isDeleted).length) as int;
      deletedCount = (summary?['total_deleted_count'] as num?)?.toInt() ?? transactions.where((t) => t.isDeleted).length;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter card with Category, Subcategory, Date, Status, Payment mode
          _buildReportsFilterCard(context, state, notifier),
          const SizedBox(height: 16),

          // KPI summary cards
          LayoutBuilder(
            builder: (context, constraints) {
              final cardW = constraints.maxWidth < 600
                  ? (constraints.maxWidth - 10) / 2
                  : (constraints.maxWidth - 20) / 3;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: cardW,
                    child: _buildKpiCard(
                      title: 'Active Total Spent',
                      amount: totalExpenses,
                      subtitle: '$activeCount transactions recorded',
                      color: const Color(0xFF1B4332),
                      icon: Icons.account_balance_wallet_rounded,
                    ),
                  ),
                  SizedBox(
                    width: cardW,
                    child: _buildKpiCard(
                      title: 'Total Records',
                      amount: transactions.length.toDouble(),
                      isCount: true,
                      subtitle: '$activeCount active, $deletedCount deleted',
                      color: const Color(0xFF2563EB),
                      icon: Icons.receipt_long_rounded,
                    ),
                  ),
                  SizedBox(
                    width: cardW,
                    child: _buildKpiCard(
                      title: 'Deleted Total',
                      amount: deletedExpenses,
                      subtitle: '$deletedCount deleted items',
                      color: const Color(0xFFB91C1C),
                      icon: Icons.delete_outline_rounded,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Download actions & table header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text('Download Excel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E7145),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: state.isExporting ? null : () => notifier.exportExpenseReportToExcel(),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text('Download PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD9381E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: state.isExporting ? null : () => notifier.exportExpenseReportToPdf(),
                    ),
                  ],
                ),
                Text(
                  '${transactions.length} records',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Transactions Data Table
          state.isLoadingExpenses
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
                )
              : transactions.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          const Text(
                            'No financial expense transactions recorded for this period.',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Expenses recorded on the Cashier POS screen will appear here in real time.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                              headingTextStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppColors.textPrimary,
                              ),
                              dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                              columns: const [
                                DataColumn(label: Text('EXPENSE CATEGORY')),
                                DataColumn(label: Text('AMOUNT')),
                                DataColumn(label: Text('DATE & TIME')),
                                DataColumn(label: Text('METHOD')),
                                DataColumn(label: Text('NOTES & AUDIT')),
                                DataColumn(label: Text('RECORDED BY')),
                                DataColumn(label: Text('STATUS')),
                              ],
                              rows: [
                                ...transactions.map((t) {
                                final isDeleted = t.isDeleted || t.status == 'deleted';
                                final catIcon = _getCategoryIcon(t.expenseName);
                                final catColor = _getCategoryColor(t.expenseName);
                                final matchingSub = isSubCategoryActive
                                    ? t.subExpenses.where((s) => s.name.trim().toLowerCase() == selectedSubCategory.trim().toLowerCase()).firstOrNull
                                    : null;
                                final displayAmount = matchingSub != null ? matchingSub.amount : t.amount;

                                return DataRow(
                                  color: isDeleted ? WidgetStateProperty.all(const Color(0xFFFEF2F2)) : null,
                                  cells: [
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(catIcon, size: 16, color: catColor),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                t.expenseName,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  decoration: isDeleted ? TextDecoration.lineThrough : null,
                                                  color: isDeleted ? Colors.grey : AppColors.textPrimary,
                                                ),
                                              ),
                                              if (matchingSub != null) ...[
                                                const SizedBox(height: 2),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE0F2FE),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: const Color(0xFFBAE6FD)),
                                                  ),
                                                  child: Text(
                                                    'Sub: ${matchingSub.name}',
                                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                                                  ),
                                                ),
                                              ] else if (t.hasSubExpenses) ...[
                                                const SizedBox(height: 2),
                                                InkWell(
                                                  onTap: () => _showSubExpensesDialog(context, t),
                                                  borderRadius: BorderRadius.circular(4),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFE8F5E9),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: const Color(0xFFC8E6C9)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.list_alt_rounded, size: 10, color: Color(0xFF2D6A4F)),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          '${t.subExpenses.length} items (tap to view)',
                                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              if (t.isEdited)
                                                Text(
                                                  '⚠️ Edited ${t.editedAt != null ? DateFormat('dd/MM hh:mm a').format(t.editedAt!) : ''}',
                                                  style: const TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.bold),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '₹${displayAmount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isDeleted ? Colors.red.shade700 : const Color(0xFF1B4332),
                                              decoration: isDeleted ? TextDecoration.lineThrough : null,
                                            ),
                                          ),
                                          if (matchingSub != null && t.amount != displayAmount)
                                            Text(
                                              'Bill: ₹${t.amount.toStringAsFixed(2)}',
                                              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                                            )
                                          else if (t.originalAmount != null && t.originalAmount != t.amount)
                                            Text(
                                              'Orig: ₹${t.originalAmount!.toStringAsFixed(2)}',
                                              style: TextStyle(fontSize: 9, color: Colors.grey.shade500, decoration: TextDecoration.lineThrough),
                                            ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            DateFormat('dd/MM/yyyy hh:mm a').format(t.createdAt),
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          if (DateFormat('yyyy-MM-dd').format(t.expenseDate) != DateFormat('yyyy-MM-dd').format(t.createdAt))
                                            Text(
                                              'Period: ${DateFormat('dd/MM/yyyy').format(t.expenseDate)}',
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                            ),
                                        ],
                                      ),
                                    ),
                                    DataCell(Text(t.paymentMethodLabel)),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 220),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (t.displayNotes.isNotEmpty)
                                              Text(t.displayNotes, maxLines: 2, overflow: TextOverflow.ellipsis),
                                            if (isDeleted && t.deleteReason != null)
                                              Text('Del reason: ${t.deleteReason}', style: const TextStyle(fontSize: 10, color: Colors.red), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            if (t.isEdited && t.editReason != null)
                                              Text('Edit reason: ${t.editReason}', style: const TextStyle(fontSize: 10, color: Color(0xFFB45309)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(t.recordedByName)),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isDeleted ? Colors.red.shade50 : Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: isDeleted ? Colors.red.shade200 : Colors.green.shade200),
                                        ),
                                        child: Text(
                                          isDeleted ? 'DELETED' : 'ACTIVE',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            color: isDeleted ? Colors.red.shade700 : Colors.green.shade700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                              if (transactions.isNotEmpty)
                                DataRow(
                                  color: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
                                  cells: [
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.calculate_rounded, size: 16, color: Color(0xFF1B4332)),
                                          const SizedBox(width: 8),
                                          Text(
                                            'GROSS TOTAL (${transactions.length} records)',
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B4332), fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '₹${totalExpenses.toStringAsFixed(2)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B4332)),
                                      ),
                                    ),
                                    const DataCell(Text('-', style: TextStyle(color: Colors.grey))),
                                    const DataCell(Text('-', style: TextStyle(color: Colors.grey))),
                                    const DataCell(Text('Active Total Spent', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF2D6A4F)))),
                                    const DataCell(Text('-', style: TextStyle(color: Colors.grey))),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2E7D32),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'ACTIVE TOTAL',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white),
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
        ],
      ),
    );
  }

  void _showSubExpensesDialog(BuildContext context, ExpenseTransaction transaction) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: Color(0xFF2D6A4F), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${transaction.expenseName} Breakdown',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F8F4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Expense Amount:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(
                      '₹${transaction.amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B4332)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('ITEMIZED SUB-EXPENSES:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 6),
              ...transaction.subExpenses.map((sub) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6, color: Color(0xFF2D6A4F)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    ),
                    Text(
                      '₹${sub.amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B4332)),
                    ),
                  ],
                ),
              )),
              if (transaction.displayNotes.isNotEmpty) ...[
                const Divider(height: 20),
                Text(
                  'Notes: ${transaction.displayNotes}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsFilterCard(BuildContext context, AdminState state, AdminNotifier notifier) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AdminDateFilter.values.map((filter) {
                final isSelected = state.dateFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: InkWell(
                    onTap: () {
                      if (filter == AdminDateFilter.custom) {
                        _pickCustomDate(context, state, notifier);
                      } else {
                        notifier.setDateFilter(filter);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primaryLight : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? AppColors.primaryGreen : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        filter.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppColors.primaryGreen : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Filters row: Status filter, Category filter & Payment Method filter
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              // Category filter
              SizedBox(
                width: 175,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: state.selectedExpenseDefinitionFilter,
                      hint: const Text('All Categories', style: TextStyle(fontSize: 12)),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Categories', style: TextStyle(fontSize: 12)),
                        ),
                        ...state.expenseDefinitions.map((d) {
                          return DropdownMenuItem<String?>(
                            value: d.id,
                            child: Text(d.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        notifier.setExpenseFilters(
                          definitionId: val,
                          clearDefinition: val == null,
                          expenseType: state.selectedExpenseTypeFilter,
                          paymentMethod: state.selectedExpensePaymentMethodFilter,
                          statusFilter: state.selectedExpenseStatusFilter,
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Subcategory filter (dynamically available when category has subcategories)
              Builder(
                builder: (context) {
                  final selectedDef = state.selectedExpenseDefinitionFilter != null
                      ? state.expenseDefinitions.where((d) => d.id == state.selectedExpenseDefinitionFilter).firstOrNull
                      : null;
                  if (selectedDef == null || !selectedDef.hasSubExpenses) {
                    return const SizedBox.shrink();
                  }

                  return SizedBox(
                    width: 175,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2D6A4F), width: 1.2),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: state.selectedExpenseSubCategoryFilter,
                          hint: const Text('All Subcategories', style: TextStyle(fontSize: 12)),
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, size: 20, color: Color(0xFF2D6A4F)),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Subcategories', style: TextStyle(fontSize: 12)),
                            ),
                            ...selectedDef.defaultSubExpenses.map((subName) {
                              return DropdownMenuItem<String?>(
                                value: subName,
                                child: Text(
                                  subName,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            notifier.setExpenseSubCategoryFilter(val);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Status filter (Active vs Deleted)
              SizedBox(
                width: 145,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: state.selectedExpenseStatusFilter,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Status', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'active_only', child: Text('Active Only', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(
                          value: 'deleted_only',
                          child: Text(
                            'Deleted Only',
                            style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          notifier.setExpenseFilters(
                            statusFilter: val,
                            definitionId: state.selectedExpenseDefinitionFilter,
                            expenseType: state.selectedExpenseTypeFilter,
                            paymentMethod: state.selectedExpensePaymentMethodFilter,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),

              // Payment Method filter
              SizedBox(
                width: 145,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: state.selectedExpensePaymentMethodFilter,
                      hint: const Text('All Methods', style: TextStyle(fontSize: 12)),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All Methods', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'cash', child: Text('Cash', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'upi', child: Text('UPI', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'card', child: Text('Card', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'other', child: Text('Other', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (val) {
                        notifier.setExpenseFilters(
                          paymentMethod: val,
                          definitionId: state.selectedExpenseDefinitionFilter,
                          expenseType: state.selectedExpenseTypeFilter,
                          statusFilter: state.selectedExpenseStatusFilter,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required double amount,
    required String subtitle,
    required Color color,
    required IconData icon,
    bool isCount = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              isCount ? '${amount.toInt()}' : '₹${amount.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Future<void> _pickCustomDate(BuildContext context, AdminState state, AdminNotifier notifier) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: state.customStartDate,
        end: state.customEndDate,
      ),
    );

    if (picked != null) {
      notifier.setDateFilter(
        AdminDateFilter.custom,
        customStart: picked.start,
        customEnd: picked.end,
      );
    }
  }
}