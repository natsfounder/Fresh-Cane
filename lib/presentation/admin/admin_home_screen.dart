import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../services/subscription_service.dart';
import '../../state/admin_provider.dart';
import '../../state/admin_state.dart';
import '../../state/auth_provider.dart';
import '../common/exit_confirmation_dialog.dart';
import '../common/user_profile_badge.dart';
import 'views/admin_audit_logs_view.dart';
import 'views/admin_dashboard_view.dart';
import 'views/admin_expenses_view.dart';
import 'views/admin_menu_view.dart';
import 'views/admin_reports_view.dart';
import 'views/admin_settings_view.dart';
import 'views/admin_staff_view.dart';
import 'views/admin_tables_view.dart';

/// Comprehensive Admin Module for Fresh Cane POS.
///
/// Features:
/// - Executive Business Dashboard with KPI metrics, live orders, sales trends
/// - 9 standard operational reports with on-demand Excel (.xlsx) and PDF export
/// - Complete Expense Management & Recurring Schedules (Mandatory & Occasional)
/// - Product & Menu management with instant stock availability toggling
/// - Table occupancy & capacity management
/// - Customer records & spend tracking
/// - Multi-role staff management & RBAC assignment
/// - Immutable audit logs viewer
/// - Store & receipt configuration
class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen> {
  final List<Map<String, dynamic>> _navItems = [
    {'title': 'Dashboard', 'icon': Icons.dashboard_outlined, 'activeIcon': Icons.dashboard},
    {'title': 'Reports', 'icon': Icons.bar_chart_outlined, 'activeIcon': Icons.bar_chart},
    {'title': 'Expenses', 'icon': Icons.receipt_long_outlined, 'activeIcon': Icons.receipt_long},
    {'title': 'Menu & Products', 'icon': Icons.restaurant_menu_outlined, 'activeIcon': Icons.restaurant_menu},
    {'title': 'Tables', 'icon': Icons.table_restaurant_outlined, 'activeIcon': Icons.table_restaurant},
    {'title': 'Staff & Access', 'icon': Icons.manage_accounts_outlined, 'activeIcon': Icons.manage_accounts},
    {'title': 'Audit Logs', 'icon': Icons.security_outlined, 'activeIcon': Icons.security},
    {'title': 'Settings', 'icon': Icons.settings_outlined, 'activeIcon': Icons.settings},
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);

    // Guard: Listen for software freeze to redirect to warning screen
    ref.listen<bool>(softwareFrozenProvider, (prev, isFrozen) {
      if (isFrozen && mounted) {
        Navigator.of(context).pushReplacementNamed('/software-frozen');
      }
    });

    // Show transient notification if error or success message
    ref.listen<String?>(adminProvider.select((s) => s.errorMessage), (prev, next) {
      if (next != null && next.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });

    ref.listen<String?>(adminProvider.select((s) => s.successMessage), (prev, next) {
      if (next != null && next.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: AppColors.primaryGreen,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await ExitConfirmationDialog.show(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.borderLight,
          ),
        ),
        leading: Builder(
          builder: (context) {
            final isWide = MediaQuery.of(context).size.width >= 900;
            if (isWide) {
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primaryGreen, size: 20),
                ),
              );
            }
            return IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Fresh Cane',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentGoldLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.accentGoldBorder),
                  ),
                  child: const Text(
                    'ADMIN',
                    style: TextStyle(
                      color: AppColors.woodWarm,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              _navItems[state.selectedNavIndex]['title'],
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: UserProfileBadge(isDarkText: true),
          ),
        ],
      ),
      drawer: MediaQuery.of(context).size.width < 900
          ? _buildDrawer(state, notifier)
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          if (isWide) {
            return Row(
              children: [
                // Desktop / Tablet Sidebar Navigation
                _buildSidebar(state, notifier),
                VerticalDivider(width: 1, color: Colors.grey.shade200),
                // Main Content View
                Expanded(
                  child: _buildCurrentView(state.selectedNavIndex),
                ),
              ],
            );
          } else {
            // Mobile / Compact View
            return Column(
              children: [
                // Quick Navigation Horizontal Strip on Mobile
                _buildMobileNavStrip(state, notifier),
                Expanded(
                  child: _buildCurrentView(state.selectedNavIndex),
                ),
              ],
            );
          }
        },
      ),
      ),
    );
  }

  Widget _buildCurrentView(int index) {
    switch (index) {
      case 0:
        return const AdminDashboardView();
      case 1:
        return const AdminReportsView();
      case 2:
        return const AdminExpensesView();
      case 3:
        return const AdminMenuView();
      case 4:
        return const AdminTablesView();
      case 5:
        return const AdminStaffView();
      case 6:
        return const AdminAuditLogsView();
      case 7:
        return const AdminSettingsView();
      default:
        return const AdminDashboardView();
    }
  }

  Widget _buildSidebar(AdminState state, dynamic notifier) {
    return Container(
      width: 230,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 14),
        children: [
          ...List.generate(_navItems.length, (index) {
            final item = _navItems[index];
            final isSelected = state.selectedNavIndex == index;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
              child: ListTile(
                dense: true,
                selected: isSelected,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                selectedTileColor: AppColors.primaryLight,
                leading: Icon(
                  isSelected ? item['activeIcon'] : item['icon'],
                  color: isSelected ? AppColors.primaryGreen : Colors.grey.shade600,
                  size: 20,
                ),
                title: Text(
                  item['title'],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                  ),
                ),
                onTap: () => notifier.setNavIndex(index),
              ),
            );
          }),
          const Divider(height: 20, color: AppColors.borderLight),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const Icon(Icons.logout_rounded, color: Colors.red, size: 20),
              title: const Text(
                'Log out',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),
              onTap: () => _confirmLogout(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(AdminState state, dynamic notifier) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            width: double.infinity,
            color: AppColors.primaryLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryGreen,
                  child: const Icon(Icons.storefront, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Fresh Cane POS',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const Text(
                  'Admin Management Center',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = state.selectedNavIndex == index;

                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: AppColors.primaryLight,
                  leading: Icon(
                    isSelected ? item['activeIcon'] : item['icon'],
                    color: isSelected ? AppColors.primaryGreen : Colors.grey.shade600,
                    size: 20,
                  ),
                  title: Text(
                    item['title'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppColors.primaryGreen : Colors.black87,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    notifier.setNavIndex(index);
                  },
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.red.shade100),
                ),
                tileColor: Colors.red.shade50.withValues(alpha: 0.5),
                leading: const Icon(Icons.logout_rounded, color: Colors.red, size: 22),
                title: const Text(
                  'Log out',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                subtitle: const Text(
                  'Exit Admin and sign out',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmLogout(context);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.red, size: 22),
            SizedBox(width: 10),
            Text('Confirm Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Are you sure you want to log out of the Admin panel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/login',
                  (route) => false,
                );
              }
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileNavStrip(AdminState state, dynamic notifier) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _navItems.length,
        itemBuilder: (context, index) {
          final item = _navItems[index];
          final isSelected = state.selectedNavIndex == index;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => notifier.setNavIndex(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppColors.primaryGreen : AppColors.borderMedium,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? item['activeIcon'] : item['icon'],
                      size: 16,
                      color: isSelected ? AppColors.primaryGreen : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item['title'],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                        color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
