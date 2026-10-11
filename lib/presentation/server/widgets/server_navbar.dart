import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../today_orders_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/responsive.dart';
import '../../common/user_profile_badge.dart';

/// Top Navbar for the Fresh Cane Server flow.
///
/// Features:
/// - Left: Hamburger menu icon that triggers the shrink side panel.
/// - Center: Fresh Cane logo mark + "Fresh Cane" wordmark.
/// - Right: Tappable Active/Inactive shift status indicator pill.
class ServerNavbar extends ConsumerStatefulWidget {
  final VoidCallback onToggleDrawer;
  final bool isDrawerOpen;

  const ServerNavbar({
    super.key,
    required this.onToggleDrawer,
    required this.isDrawerOpen,
  });

  @override
  ConsumerState<ServerNavbar> createState() => _ServerNavbarState();
}

class _ServerNavbarState extends ConsumerState<ServerNavbar> {

  @override
  Widget build(BuildContext context) {
    final navHeight = Responsive.navbarHeight(context);

    return Container(
      height: navHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F2E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF265036), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ─── Left: Hamburger Menu Icon ─────────────────────────────────────
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onToggleDrawer();
              },
              child: Container(
                width: AppColors.minTouchTarget,
                height: AppColors.minTouchTarget,
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    widget.isDrawerOpen
                        ? Icons.menu_open_rounded
                        : Icons.menu_rounded,
                    key: ValueKey(widget.isDrawerOpen),
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // ─── Center: Fresh Cane Brand (Flexibly centered) ──────────────────
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with subtle green glow
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondaryGreen.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/images/fresh_cane_logo.png',
                    height: 28,
                    errorBuilder: (_, _, _) => Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2D6A4F),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.eco_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Fresh Cane',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.4,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ─── Quick Access: Today's Orders ───────────────────────────────────
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TodayOrdersScreen(),
                  ),
                );
              },
              child: Container(
                width: AppColors.minTouchTarget,
                height: AppColors.minTouchTarget,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 22,
                  color: Color(0xFF7CB342),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ─── Right: User Profile Avatar & Switcher Badge ────────────────────
          const UserProfileBadge(isDarkText: false),
        ],
      ),
    );
  }
}
