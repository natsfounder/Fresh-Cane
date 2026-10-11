import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/responsive.dart';
import '../../services/subscription_service.dart';
import '../../state/auth_provider.dart';
import '../../state/auth_state.dart';

/// POS Login Screen with official branding, username, password, login, and Forgot Password.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    String usernameOrEmail = _emailController.text.trim();
    if (usernameOrEmail.toLowerCase() == 'superadmin@freshcane' ||
        usernameOrEmail.toLowerCase() == 'superadmin') {
      usernameOrEmail = 'superadmin@freshcane.com';
    } else if (!usernameOrEmail.contains('@')) {
      usernameOrEmail = '$usernameOrEmail@freshcane.com';
    }
    final password = _passwordController.text;

    await ref.read(authProvider.notifier).signInEmployee(
          email: usernameOrEmail,
          password: password,
        );
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primaryGreen, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                'Forgot Password?',
                style: AppTextStyles.h2.copyWith(
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Staff passwords (Cashier & Server) are controlled by your Store Administrator.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to get your password reset:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryDark),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Contact your Store Administrator or Manager.\n'
                      '2. The Admin will open Staff & Access and set your new password instantly.\n'
                      '3. You will be able to log in immediately.',
                      style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK, Got It', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    // Listen for authenticated state to navigate to the appropriate role screen
    ref.listen<AuthState>(authProvider, (_, next) async {
      if (next.status == AuthStatus.authenticated && next.userProfile != null) {
        final profile = next.userProfile!;

        // 1. Master SuperAdmin -> /super-admin console (always accessible)
        if (profile.isMasterSuperAdminUser) {
          if (context.mounted) {
            Navigator.of(context).pushReplacementNamed('/super-admin');
          }
          return;
        }

        // 2. Check if software is frozen -> /software-frozen
        final isFrozen = await ref.read(softwareFrozenProvider.notifier).checkFreezeStatus();
        if (isFrozen && context.mounted) {
          Navigator.of(context).pushReplacementNamed('/software-frozen');
          return;
        }

        if (!context.mounted) return;

        if (profile.role == AppConstants.roleCashier || profile.isCashier) {
          Navigator.of(context).pushReplacementNamed('/cashier');
        } else if (profile.role == AppConstants.roleServer || profile.isServer) {
          Navigator.of(context).pushReplacementNamed('/server');
        } else if (profile.role == AppConstants.roleSuperAdmin || profile.isSuperAdmin) {
          Navigator.of(context).pushReplacementNamed('/admin');
        } else {
          Navigator.of(context).pushReplacementNamed('/server');
        }
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A2215),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Subtle ambient cafe background elements spread across the screen
          const Positioned.fill(
            child: IgnorePointer(
              child: _CafeAmbientBackground(),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.value(context, mobile: 16.0, tablet: 24.0),
                  vertical: Responsive.value(context, mobile: 16.0, tablet: 24.0),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.maxContentWidth(context),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF133824),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF265036),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: AppColors.secondaryGreen.withValues(alpha: 0.12),
                          blurRadius: 20,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        Responsive.value(context, mobile: 24.0, tablet: 32.0),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Fresh Cane Official Branding Logo
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.secondaryGreen.withValues(alpha: 0.25),
                                      blurRadius: 20,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  'assets/images/fresh_cane_logo.png',
                                  width: Responsive.value(context, mobile: 76.0, tablet: 88.0),
                                  height: Responsive.value(context, mobile: 84.0, tablet: 96.0),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Brand Name & Tagline
                            Center(
                              child: Text(
                                'Fresh Cane',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Center(
                              child: Text(
                                'Good Food • Fresh Vibes',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF7CB342),
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Welcome Message
                            Center(
                              child: Text(
                                'Welcome Back',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Center(
                              child: Text(
                                'Sign in to continue to your account.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFB4C8BA),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),



                            // Error Banner if present
                            if (authState.errorMessage != null &&
                                authState.errorMessage!.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B1515),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.redAccent.shade200),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: Colors.redAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        authState.errorMessage!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],

                            // Username or Email Field
                            const Text(
                              'Username or Email',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD1E0D7),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              key: const ValueKey('login_email_field'),
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              enabled: !isLoading,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFF0F2E1E),
                                hintText: 'Enter username or email',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF7E9A87),
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.person_outline_rounded,
                                  size: 20,
                                  color: Color(0xFF7CB342),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF265036)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF265036)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF52B788),
                                    width: 1.8,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter username or email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Password Field
                            Text(
                              'Password',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD1E0D7),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              key: const ValueKey('login_password_field'),
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              enabled: !isLoading,
                              onFieldSubmitted: (_) =>
                                  FocusScope.of(context).unfocus(),
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFF0F2E1E),
                                hintText: '••••••••',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF7E9A87),
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 20,
                                  color: Color(0xFF7CB342),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                    color: const Color(0xFF7E9A87),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF265036)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF265036)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF52B788),
                                    width: 1.8,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),

                            // Forgot Password Action
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: const ValueKey('forgot_password_button'),
                                onPressed:
                                    isLoading ? null : _showForgotPasswordDialog,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 6, horizontal: 0),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF74C69D),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Sign In Action Button
                            ElevatedButton(
                              key: const ValueKey('sign_in_button'),
                              onPressed: isLoading ? null : _handleSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D6A4F),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 3,
                                shadowColor: const Color(0xFF2D6A4F).withValues(alpha: 0.5),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Text(
                                      'Login',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 22),

                            // Footer Note
                            Center(
                              child: Column(
                                children: [
                                  const Text(
                                    'Fresh Cane',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6B8B77),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Cafe POS & Management System • v${AppConfig.appVersion}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF557361),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual 3D cafe item with perspective tilt, vibrant dual-tone gradients, and claymorphic lighting.
class _Cafe3DItem {
  final IconData icon;
  final double x; // Relative horizontal position (0.0 to 1.0)
  final double y; // Relative vertical position (0.0 to 1.0)
  final double baseSize;
  final Color bgStart;
  final Color bgEnd;
  final Color iconColor;
  final double tiltX;
  final double tiltY;
  final double rotation;
  final bool wideOnly;

  const _Cafe3DItem({
    required this.icon,
    required this.x,
    required this.y,
    this.baseSize = 52,
    required this.bgStart,
    required this.bgEnd,
    this.iconColor = Colors.white,
    this.tiltX = 0.0,
    this.tiltY = 0.0,
    this.rotation = 0.0,
    this.wideOnly = false,
  });
}

/// Ambient cafe-themed background displaying floating 3D sculpted shapes in vibrant colors:
/// burgers, pizza, coffee mugs, fresh cane drinks, pastries, ice cream, and desserts.
///
/// Fully responsive across mobile, tablet, portrait, and landscape orientations without
/// interfering with login card inputs or touch events.
class _CafeAmbientBackground extends StatelessWidget {
  const _CafeAmbientBackground();

  static const List<_Cafe3DItem> _items = [
    // 🍔 3D Burger - Top Left
    _Cafe3DItem(
      icon: Icons.lunch_dining_rounded,
      x: 0.08,
      y: 0.06,
      baseSize: 54,
      bgStart: Color(0xFFFFB74D), // Golden brioche bun
      bgEnd: Color(0xFFE65100),   // Caramelized roast
      tiltX: 0.12,
      tiltY: -0.15,
      rotation: -0.22,
    ),
    // 🍕 3D Pizza - Top Right
    _Cafe3DItem(
      icon: Icons.local_pizza_rounded,
      x: 0.92,
      y: 0.06,
      baseSize: 54,
      bgStart: Color(0xFFFF7043), // Vibrant mozzarella
      bgEnd: Color(0xFFD84315),   // Baked marinara
      tiltX: -0.12,
      tiltY: 0.15,
      rotation: 0.25,
    ),
    // ☕ 3D Coffee Mug - Top Center
    _Cafe3DItem(
      icon: Icons.local_cafe_rounded,
      x: 0.50,
      y: 0.03,
      baseSize: 46,
      bgStart: Color(0xFFA1887F), // Creamy latte
      bgEnd: Color(0xFF4E342E),   // Dark roast espresso
      tiltX: 0.05,
      tiltY: 0.0,
      rotation: -0.08,
    ),
    // 🥤 3D Fresh Cane Juice - Upper Left Edge
    _Cafe3DItem(
      icon: Icons.emoji_food_beverage_rounded,
      x: 0.06,
      y: 0.28,
      baseSize: 50,
      bgStart: Color(0xFFC0CA33), // Fresh lime cane
      bgEnd: Color(0xFF33691E),   // Deep forest green
      tiltX: 0.10,
      tiltY: -0.18,
      rotation: 0.15,
    ),
    // 🥐 3D Butter Croissant - Upper Right Edge
    _Cafe3DItem(
      icon: Icons.bakery_dining_rounded,
      x: 0.94,
      y: 0.28,
      baseSize: 50,
      bgStart: Color(0xFFFFE082), // Flaky butter
      bgEnd: Color(0xFFFFA000),   // Baked honey crust
      tiltX: -0.10,
      tiltY: 0.18,
      rotation: -0.20,
    ),
    // 🍟 3D Crispy Fries - Lower Left Edge
    _Cafe3DItem(
      icon: Icons.fastfood_rounded,
      x: 0.06,
      y: 0.72,
      baseSize: 50,
      bgStart: Color(0xFFEF5350), // Diner crimson
      bgEnd: Color(0xFFB71C1C),   // Deep ketchup red
      iconColor: Color(0xFFFFEB3B), // Golden yellow fries
      tiltX: 0.14,
      tiltY: -0.12,
      rotation: 0.18,
    ),
    // 🍦 3D Ice Cream Cone - Lower Right Edge
    _Cafe3DItem(
      icon: Icons.icecream_rounded,
      x: 0.94,
      y: 0.72,
      baseSize: 50,
      bgStart: Color(0xFFF48FB1), // Strawberry swirl
      bgEnd: Color(0xFFC2185B),   // Rich berry
      tiltX: -0.14,
      tiltY: 0.12,
      rotation: -0.15,
    ),
    // 🍰 3D Berry Cake - Bottom Left
    _Cafe3DItem(
      icon: Icons.cake_rounded,
      x: 0.10,
      y: 0.94,
      baseSize: 52,
      bgStart: Color(0xFFCE93D8), // Lavender cream
      bgEnd: Color(0xFF6A1B9A),   // Deep royal berry
      tiltX: -0.10,
      tiltY: -0.12,
      rotation: -0.18,
    ),
    // 🍜 3D Ramen Bowl - Bottom Right
    _Cafe3DItem(
      icon: Icons.ramen_dining_rounded,
      x: 0.90,
      y: 0.94,
      baseSize: 52,
      bgStart: Color(0xFFFF8A65), // Terracotta clay
      bgEnd: Color(0xFFBF360C),   // Spicy chili
      tiltX: -0.10,
      tiltY: 0.12,
      rotation: 0.20,
    ),
    // 🍩 3D Glazed Donut - Bottom Center
    _Cafe3DItem(
      icon: Icons.cookie_rounded,
      x: 0.50,
      y: 0.97,
      baseSize: 44,
      bgStart: Color(0xFFFFCC80), // Golden dough
      bgEnd: Color(0xFFE65100),   // Warm caramel
      tiltX: -0.05,
      tiltY: 0.0,
      rotation: 0.10,
    ),

    // ── Extended Flank Items for Tablet, Desktop & Landscape ──
    // 🥪 3D Deli Sandwich
    _Cafe3DItem(
      icon: Icons.set_meal_rounded,
      x: 0.18,
      y: 0.18,
      baseSize: 54,
      bgStart: Color(0xFF81C784), // Garden mint
      bgEnd: Color(0xFF2E7D32),   // Deep botanical
      tiltX: 0.12,
      tiltY: -0.10,
      rotation: -0.14,
      wideOnly: true,
    ),
    // 🍽️ 3D Meal Platter
    _Cafe3DItem(
      icon: Icons.restaurant_rounded,
      x: 0.82,
      y: 0.18,
      baseSize: 54,
      bgStart: Color(0xFF80CBC4), // Aqua marine
      bgEnd: Color(0xFF00695C),   // Deep emerald
      tiltX: -0.12,
      tiltY: 0.10,
      rotation: 0.16,
      wideOnly: true,
    ),
    // 🍔 3D Cheeseburger Deluxe
    _Cafe3DItem(
      icon: Icons.lunch_dining_rounded,
      x: 0.14,
      y: 0.50,
      baseSize: 56,
      bgStart: Color(0xFFFFB300), // Melted cheddar
      bgEnd: Color(0xFFF57C00),   // Toasted crust
      tiltX: 0.08,
      tiltY: -0.18,
      rotation: 0.12,
      wideOnly: true,
    ),
    // 🍕 3D Supreme Pizza
    _Cafe3DItem(
      icon: Icons.local_pizza_rounded,
      x: 0.86,
      y: 0.50,
      baseSize: 56,
      bgStart: Color(0xFFFF5722), // Zesty pepper
      bgEnd: Color(0xFFBF360C),   // Oven charred
      tiltX: -0.08,
      tiltY: 0.18,
      rotation: -0.18,
      wideOnly: true,
    ),
    // ☕ 3D Cafe Latte
    _Cafe3DItem(
      icon: Icons.coffee_rounded,
      x: 0.18,
      y: 0.82,
      baseSize: 52,
      bgStart: Color(0xFFBCAAA4), // Cappuccino foam
      bgEnd: Color(0xFF5D4037),   // Mocha brew
      tiltX: -0.14,
      tiltY: -0.08,
      rotation: 0.22,
      wideOnly: true,
    ),
    // 🥡 3D Takeout Box
    _Cafe3DItem(
      icon: Icons.takeout_dining_rounded,
      x: 0.82,
      y: 0.82,
      baseSize: 52,
      bgStart: Color(0xFF90CAF9), // Sky blue
      bgEnd: Color(0xFF1565C0),   // Royal cobalt
      tiltX: -0.14,
      tiltY: 0.08,
      rotation: -0.16,
      wideOnly: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w <= 0 || h <= 0) return const SizedBox.shrink();

        final isWide = w >= 600 || w > h;
        // Dynamically scale 3D shapes proportionally to screen size
        final scale = (w / 450).clamp(0.85, 1.20);

        return ClipRect(
          child: Stack(
            children: [
              for (final item in _items)
                if (!item.wideOnly || isWide)
                  Positioned(
                    left: (item.x * w) - (item.baseSize * scale / 2),
                    top: (item.y * h) - (item.baseSize * scale / 2),
                    child: _buildItem(item, scale),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItem(_Cafe3DItem item, double scale) {
    final size = item.baseSize * scale;

    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002) // Perspective foreshortening
        ..rotateX(item.tiltX)
        ..rotateY(item.tiltY)
        ..rotateZ(item.rotation),
      alignment: Alignment.center,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [item.bgStart, item.bgEnd],
          ),
          boxShadow: [
            // Deep 3D cast shadow with rich color tint
            BoxShadow(
              color: item.bgEnd.withValues(alpha: 0.45),
              blurRadius: 14,
              spreadRadius: 1,
              offset: const Offset(4, 7),
            ),
            // Contact shadow
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 6,
              offset: const Offset(1, 3),
            ),
            // Top-left 3D highlight (light reflection)
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.70),
              blurRadius: 5,
              offset: const Offset(-2, -3),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Top specular gloss reflection
            Positioned(
              top: size * 0.08,
              left: size * 0.12,
              child: Container(
                width: size * 0.46,
                height: size * 0.22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.15),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.60),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // 3D Embossed Icon
            Icon(
              item.icon,
              size: size * 0.54,
              color: item.iconColor,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  offset: const Offset(1.5, 2.0),
                  blurRadius: 3,
                ),
                Shadow(
                  color: Colors.white.withValues(alpha: 0.35),
                  offset: const Offset(-0.8, -0.8),
                  blurRadius: 1.5,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

