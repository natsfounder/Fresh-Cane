import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../state/auth_provider.dart';
import 'account_switcher_sheet.dart';

/// User Profile Avatar Badge displayed in top navbars/appbars.
///
/// Clean vertical widget:
/// - Avatar Icon containing First Name & Last Name initials inside
/// - Directly below the avatar: "Server", "Biller", or "Admin"
///
/// Behavior on tap:
/// - If ONLY ONE account: displays ONLY the current role (e.g. "Server"),
///   with NO name and NO email.
/// - If MORE THAN ONE account: opens the Instagram-style profile switcher sheet.
class UserProfileBadge extends ConsumerWidget {
  final bool isDarkText;

  const UserProfileBadge({
    super.key,
    this.isDarkText = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final profile = authState.userProfile;
    final accounts = authState.availableAccounts;

    final fullName = profile?.fullName ?? 'Staff Member';
    final role = profile?.role ?? AppConstants.roleServer;

    // Generate First Name & Last Name initials
    String initials = 'S';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final f = parts[0].isNotEmpty ? parts[0][0] : '';
      final l = parts[1].isNotEmpty ? parts[1][0] : '';
      initials = '$f$l'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      initials = parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }

    // Role display: Server / Biller / Admin
    String roleDisplayName;
    Color roleColor;
    switch (role) {
      case AppConstants.roleServer:
        roleDisplayName = 'Server';
        roleColor = AppColors.primaryGreen;
        break;
      case AppConstants.roleCashier:
        roleDisplayName = 'Biller';
        roleColor = AppColors.warning;
        break;
      case AppConstants.roleSuperAdmin:
        roleDisplayName = 'Admin';
        roleColor = AppColors.woodBrown;
        break;
      default:
        roleDisplayName = role.toUpperCase();
        roleColor = AppColors.primaryGreen;
    }

    final hasMultiple = accounts.length > 1;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
        onTap: () {
          HapticFeedback.lightImpact();

          if (hasMultiple) {
            // Case B: Multiple accounts -> Open Instagram-style profile switcher sheet
            AccountSwitcherSheet.show(context);
          } else {
            // Case A: Only one account -> Display ONLY the role (e.g. "Server"),
            // exactly as requested: no name, no email.
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: roleColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      roleDisplayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
                width: 130,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                backgroundColor: AppColors.primaryDark,
              ),
            );
          }
        },
        child: SizedBox(
          width: 48,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar circle containing First Name & Last Name initials
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 1),

              // Directly below the avatar: Server / Biller / Admin
              Text(
                roleDisplayName,
                style: TextStyle(
                  color: isDarkText ? roleColor : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  letterSpacing: 0.3,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
