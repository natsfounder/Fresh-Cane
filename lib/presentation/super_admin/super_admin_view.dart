import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../services/subscription_service.dart';
import '../../state/auth_provider.dart';

/// SuperAdmin Control Console
/// Exclusively for the software owner/vendor.
/// Contains only ONE option: The master switch for monthly payment received / freeze control.
class SuperAdminView extends ConsumerStatefulWidget {
  const SuperAdminView({super.key});

  @override
  ConsumerState<SuperAdminView> createState() => _SuperAdminViewState();
}

class _SuperAdminViewState extends ConsumerState<SuperAdminView> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() => _isLoading = true);
    await ref.read(softwareFrozenProvider.notifier).checkFreezeStatus();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleToggle(bool isFrozen) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(softwareFrozenProvider.notifier).setFreezeStatus(isFrozen);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFrozen
                ? '🔴 Software Frozen: All client logins locked.'
                : '🟢 Software Active: All logins running smoothly.',
            ),
            backgroundColor: isFrozen ? Colors.red.shade700 : AppColors.primaryGreen,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout from SuperAdmin?'),
        content: const Text('Are you sure you want to sign out of the SuperAdmin console?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(authRepositoryProvider).signOut();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFrozen = ref.watch(softwareFrozenProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium dark slate
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: AppColors.primaryGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SuperAdmin Console',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Master Software Licensing',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh Status',
            onPressed: _isLoading ? null : _refreshStatus,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFF87171)),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Status Badge Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isFrozen
                          ? const Color(0xFF450A0A) // Dark red
                          : const Color(0xFF064E3B), // Dark emerald
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isFrozen
                            ? Colors.red.shade400.withValues(alpha: 0.5)
                            : Colors.green.shade400.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isFrozen ? Icons.lock_clock_rounded : Icons.check_circle_rounded,
                          color: isFrozen ? const Color(0xFFF87171) : const Color(0xFF34D399),
                          size: 32,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isFrozen ? 'SOFTWARE IS FROZEN' : 'SOFTWARE IS ACTIVE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 0.8,
                                  color: isFrozen ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isFrozen
                                    ? 'Client logins are locked. Warning screen is active.'
                                    : 'All logins (Admin, Cashier, Server) working smoothly.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isFrozen ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // The Main Option Card (Only Option)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF334155), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF334155),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.toggle_on_outlined,
                                color: Colors.amberAccent,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Monthly Payment Control',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Divider(color: Color(0xFF334155), height: 1),
                        const SizedBox(height: 24),

                        // The Single Switch
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isFrozen ? Colors.red.shade900 : const Color(0xFF334155),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Has Monthly Payment Received?',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isFrozen
                                          ? 'OFF = Active & Smooth  |  ON = Freeze App'
                                          : 'OFF = Active & Smooth  |  ON = Freeze App',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isLoading)
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryGreen,
                                  ),
                                )
                              else
                                Transform.scale(
                                  scale: 1.15,
                                  child: Switch(
                                    value: isFrozen,
                                    activeThumbColor: Colors.redAccent,
                                    activeTrackColor: Colors.red.shade900,
                                    inactiveThumbColor: AppColors.primaryGreen,
                                    inactiveTrackColor: const Color(0xFF064E3B),
                                    onChanged: _handleToggle,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Explanation Guide
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF334155).withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: Colors.blue.shade300,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'How this control works:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade200,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '• OFF: Payment verified. The application runs smoothly for Store Admin, Cashier, and Server.\n'
                                '• ON: Payment overdue. Freezes the software and shows the warning screen to all store users with your contact number (0987654321).\n'
                                '• 100% Data Protection: No bills, products, or sales history are altered or lost.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFFCBD5E1),
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // SuperAdmin info
                  Text(
                    'Logged in as SuperAdmin (superadmin@freshcane)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
