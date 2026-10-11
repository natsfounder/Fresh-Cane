import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/responsive.dart';
import '../../services/subscription_service.dart';
import '../../state/auth_provider.dart';
import '../../state/auth_state.dart';
import '../../state/server_order_provider.dart';
import '../common/exit_confirmation_dialog.dart';
import 'views/customer_ordering_view.dart';
import 'views/table_context_view.dart';
import 'views/table_selection_view.dart';
import 'widgets/server_navbar.dart';
import 'widgets/server_side_panel.dart';

/// Main server navigation coordinator with top Navbar and shrink-style side panel.
///
/// On compact/mobile screens the side panel is rendered as a slide-over overlay
/// so that the main content is never squeezed below usable widths.
/// On tablet/desktop the original push-style animated panel is used.
class ServerHomeScreen extends ConsumerStatefulWidget {
  const ServerHomeScreen({super.key});

  @override
  ConsumerState<ServerHomeScreen> createState() => _ServerHomeScreenState();
}

class _ServerHomeScreenState extends ConsumerState<ServerHomeScreen> {
  bool _isDrawerOpen = false;

  void _toggleDrawer() {
    setState(() {
      _isDrawerOpen = !_isDrawerOpen;
    });
  }

  void _closeDrawer() {
    if (_isDrawerOpen) {
      setState(() {
        _isDrawerOpen = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Guard: Listen for software freeze to redirect to warning screen
    ref.listen<bool>(softwareFrozenProvider, (prev, isFrozen) {
      if (isFrozen && mounted) {
        Navigator.of(context).pushReplacementNamed('/software-frozen');
      }
    });

    ref.listen<AuthState>(authProvider, (_, next) {
      if (next.status == AuthStatus.unauthenticated) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });

    final orderState = ref.watch(serverOrderProvider);
    final panelWidth = Responsive.sidePanelWidth(context);
    final isMobile = Responsive.isMobile(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isDrawerOpen) {
          _closeDrawer();
          return;
        }
        if (orderState.currentStep == ServerViewStep.customerOrdering) {
          ref.read(serverOrderProvider.notifier).returnToTableContext();
          return;
        }
        if (orderState.currentStep == ServerViewStep.tableContext) {
          ref.read(serverOrderProvider.notifier).returnToTableSelection();
          return;
        }
        await ExitConfirmationDialog.show(context);
      },
      child: Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ─── 1. Fixed Top Navbar ─────────────────────────────────────────
            ServerNavbar(
              isDrawerOpen: _isDrawerOpen,
              onToggleDrawer: _toggleDrawer,
            ),

            // ─── 2. Main Content Area ────────────────────────────────────────
            Expanded(
              child: isMobile
                  ? Stack(
                      children: [
                        // Main Content View
                        _buildCurrentView(orderState),

                        // Mobile: Slide-over panel with scrim
                        if (_isDrawerOpen) ...[
                          // Scrim
                          GestureDetector(
                            onTap: _closeDrawer,
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.35),
                            ),
                          ),
                          // Side Panel as overlay
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: panelWidth,
                            child: Material(
                              elevation: 8,
                              child: ServerSidePanel(
                                onClose: _closeDrawer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Animated side panel (width 0 -> panelWidth, 200ms easeInOut)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          width: _isDrawerOpen ? panelWidth : 0,
                          clipBehavior: Clip.hardEdge,
                          decoration: const BoxDecoration(),
                          child: OverflowBox(
                            minWidth: panelWidth,
                            maxWidth: panelWidth,
                            alignment: Alignment.topLeft,
                            child: ServerSidePanel(
                              onClose: _closeDrawer,
                            ),
                          ),
                        ),

                        // Main Content View (visibly compresses/expands alongside the panel)
                        Expanded(
                          child: _buildCurrentView(orderState),
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

  Widget _buildCurrentView(ServerOrderState orderState) {
    switch (orderState.currentStep) {
      case ServerViewStep.tableSelection:
        return const TableSelectionView();
      case ServerViewStep.tableContext:
        return const TableContextView();
      case ServerViewStep.customerOrdering:
        return const CustomerOrderingView();
    }
  }
}
