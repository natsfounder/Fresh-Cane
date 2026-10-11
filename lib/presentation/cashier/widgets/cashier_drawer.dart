import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/responsive.dart';
import '../../../state/auth_provider.dart';
import '../views/cashier_today_bills_sheet.dart';

/// Drawer side menu panel for the Cashier Terminal.
/// Matches the Server Side Panel visual identity and functionality.
class CashierDrawer extends ConsumerWidget {
  const CashierDrawer({super.key});

  void _showProfileModal(BuildContext context, String name, String? phone) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        ),
        title: Text('User profile', style: AppTextStyles.h2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: $name', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 6),
            Text('Role: Cashier', style: AppTextStyles.bodyMedium),
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Phone: $phone', style: AppTextStyles.bodyMedium),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: TextStyle(color: AppColors.primaryGreen)),
          ),
        ],
      ),
    );
  }

  void _showSettingsModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        ),
        title: Text('Settings', style: AppTextStyles.h2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App: Fresh Cane POS', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 6),
            Text('Version: 1.0.0 (Cashier Build)', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 6),
            Text('Environment: Production', style: AppTextStyles.bodyMedium),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: TextStyle(color: AppColors.primaryGreen)),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        ),
        title: Text('Log out', style: AppTextStyles.h2),
        content: Text(
          'Are you sure you want to end your session and log out of the cashier terminal?',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radiusSmall),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authProvider.notifier).signOut();
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffProfile = ref.watch(currentStaffProfileProvider);
    final staffName = staffProfile?.fullName ?? 'Cashier Staff';
    final staffPhone = staffProfile?.phone;
    final panelWidth = Responsive.sidePanelWidth(context).clamp(260.0, 300.0);

    return Drawer(
      width: panelWidth,
      backgroundColor: const Color(0xFF0F2E1E),
      elevation: 16,
      child: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F2E1E),
            border: Border(
              right: BorderSide(color: Color(0xFF265036), width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── 1. Header: Cashier Profile ───────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF133824),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF265036), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    // Circular Avatar with brand gradient border
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF2D6A4F),
                            Color(0xFF7CB342),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.secondaryGreen.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F2E1E),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          staffName.isNotEmpty ? staffName[0].toUpperCase() : 'C',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            staffName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Cashier Staff',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7CB342),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ─── 2. Menu Cards ────────────────────────────────────────────────
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  children: [
                    _buildMenuCard(
                      icon: Icons.person_outline_rounded,
                      label: 'User profile',
                      onTap: () => _showProfileModal(context, staffName, staffPhone),
                    ),
                    const SizedBox(height: 10),
                    _buildMenuCard(
                      icon: Icons.receipt_long_outlined,
                      label: "Today's bills",
                      onTap: () {
                        Navigator.of(context).pop();
                        CashierTodayBillsSheet.show(context);
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildMenuCard(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () => _showSettingsModal(context),
                    ),
                    const SizedBox(height: 10),
                    _buildMenuCard(
                      icon: Icons.logout_rounded,
                      label: 'Log out',
                      isDestructive: true,
                      onTap: () => _confirmLogout(context, ref),
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

  Widget _buildMenuCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final fgColor = isDestructive ? Colors.redAccent.shade100 : Colors.white;
    final bgColor = isDestructive ? const Color(0xFF2E1515) : const Color(0xFF163E28);
    final borderColor = isDestructive ? Colors.redAccent.shade700 : const Color(0xFF265036);
    final iconColor = isDestructive ? Colors.redAccent : const Color(0xFF7CB342);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: AppColors.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: fgColor.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
