import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/staff_account.dart';
import '../../state/auth_provider.dart';
import '../../state/cashier_provider.dart';
import '../../state/server_order_provider.dart';

/// Clean Instagram-style Account Switcher Modal Bottom Sheet.
///
/// Strictly displays existing profiles for this staff member and switches
/// instantly on tap. Contains NO 'Add Account' and NO 'Logout' button.
class AccountSwitcherSheet extends ConsumerWidget {
  const AccountSwitcherSheet({super.key});

  /// Static helper to display the sheet.
  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const AccountSwitcherSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final accounts = authState.availableAccounts;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.borderMedium,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Switch Profile',
                style: AppTextStyles.h3.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Accounts List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: accounts.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final account = accounts[index];
              return _AccountTile(
                account: account,
                onTap: () async {
                  if (account.isCurrent) {
                    Navigator.of(context).pop();
                    return;
                  }

                  HapticFeedback.mediumImpact();
                  await ref.read(authProvider.notifier).switchAccount(account);
                  if (context.mounted) {
                    Navigator.of(context).pop();

                    // Navigate to appropriate role screen and re-fetch catalog
                    if (account.role == AppConstants.roleServer) {
                      ref.read(serverOrderProvider.notifier).initialize();
                      Navigator.of(context).pushReplacementNamed('/server');
                    } else if (account.role == AppConstants.roleCashier) {
                      ref.read(cashierProvider.notifier).initialize();
                      Navigator.of(context).pushReplacementNamed('/cashier');
                    } else if (account.role == AppConstants.roleSuperAdmin) {
                      Navigator.of(context).pushReplacementNamed('/admin');
                    }
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final StaffAccount account;
  final VoidCallback onTap;

  const _AccountTile({
    required this.account,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = account.isCurrent;

    Color roleColor;
    Color roleBg;
    switch (account.role) {
      case AppConstants.roleServer:
        roleColor = AppColors.primaryGreen;
        roleBg = AppColors.statusAvailableBg;
        break;
      case AppConstants.roleCashier:
        roleColor = AppColors.warning;
        roleBg = const Color(0xFFFFF8E1);
        break;
      case AppConstants.roleSuperAdmin:
        roleColor = AppColors.woodBrown;
        roleBg = const Color(0xFFEFEBE9);
        break;
      default:
        roleColor = AppColors.primaryGreen;
        roleBg = AppColors.statusAvailableBg;
    }

    return Material(
      color: isCurrent
          ? AppColors.primaryGreen.withValues(alpha: 0.06)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent
                  ? AppColors.primaryGreen.withValues(alpha: 0.5)
                  : AppColors.borderLight,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Avatar with Initials
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isCurrent ? AppColors.primaryGreen : AppColors.borderMedium,
                  shape: BoxShape.circle,
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: AppColors.primaryGreen.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  account.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Name, Role Badge and Email
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.fullName,
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight:
                                  isCurrent ? FontWeight.bold : FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: roleBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: roleColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            account.roleDisplayName,
                            style: TextStyle(
                              color: roleColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      account.email,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Checkmark for active account / Switch arrow
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                )
              else
                Text(
                  'Switch',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
