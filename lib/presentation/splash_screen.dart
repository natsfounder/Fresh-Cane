import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../services/subscription_service.dart';
import '../state/auth_provider.dart';
import '../state/auth_state.dart';

/// Visibly rendered startup splash screen without video delay, navigating smoothly based on AuthState.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _textSlideAnimation;
  late Animation<double> _pulseScaleAnimation;
  late Animation<double> _pulseGlowAnimation;
  late Animation<double> _floatAnimation;
  bool _canNavigate = false;

  @override
  void initState() {
    super.initState();

    // 1. Entrance animation (elastic pop-in + rotation + fade)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _scaleAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _rotationAnimation = Tween<double>(begin: -0.15, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _textSlideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    // 2. Continuous pulse & floating animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _pulseScaleAnimation = Tween<double>(begin: 0.98, end: 1.04).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    _pulseGlowAnimation = Tween<double>(begin: 20.0, end: 48.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    _floatAnimation = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    _entranceController.forward().then((_) {
      if (mounted) {
        _pulseController.repeat(reverse: true);
      }
    });

    // Branded impression: give 2.2 seconds to appreciate the animated logo
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() {
          _canNavigate = true;
        });
        _evaluateNavigation(ref.read(authProvider));
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _evaluateNavigation(AuthState authState) async {
    if (!mounted || !_canNavigate) return;

    switch (authState.status) {
      case AuthStatus.initial:
      case AuthStatus.loading:
        // Still initializing / resolving session
        break;

      case AuthStatus.unauthenticated:
      case AuthStatus.error:
        Navigator.of(context).pushReplacementNamed('/login');
        break;

      case AuthStatus.authenticated:
        final profile = authState.userProfile;
        if (profile == null) {
          Navigator.of(context).pushReplacementNamed('/login');
          return;
        }

        // 1. Master SuperAdmin -> /super-admin console (always accessible)
        if (profile.isMasterSuperAdminUser) {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/super-admin');
          }
          return;
        }

        // 2. Check if software is frozen -> /software-frozen
        final isFrozen = await ref.read(softwareFrozenProvider.notifier).checkFreezeStatus();
        if (isFrozen && mounted) {
          Navigator.of(context).pushReplacementNamed('/software-frozen');
          return;
        }

        if (!mounted) return;

        if (profile.isServer) {
          Navigator.of(context).pushReplacementNamed('/server');
        } else if (profile.isCashier) {
          Navigator.of(context).pushReplacementNamed('/cashier');
        } else if (profile.isSuperAdmin) {
          Navigator.of(context).pushReplacementNamed('/admin');
        } else {
          Navigator.of(context).pushReplacementNamed('/login');
        }
        break;

      case AuthStatus.missingProfile:
      case AuthStatus.inactive:
      case AuthStatus.unsupportedRole:
        // Keep visible on screen to display notice card with sign-out
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (_, next) {
      _evaluateNavigation(next);
    });

    final isNoticeState = authState.status == AuthStatus.missingProfile ||
        authState.status == AuthStatus.inactive ||
        authState.status == AuthStatus.unsupportedRole;

    return Scaffold(
      backgroundColor: const Color(0xFF081C15),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [
                  Color(0xFF1B4332),
                  Color(0xFF081C15),
                ],
              ),
            ),
          ),

          // Central Animated Brand Logo with Ripples & Floats
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_entranceController, _pulseController]),
              builder: (context, child) {
                final entranceOpacity = _opacityAnimation.value;
                final entranceScale = _scaleAnimation.value;
                final entranceRot = _rotationAnimation.value;
                final floatY = _entranceController.isCompleted ? _floatAnimation.value : 0.0;
                final pulseScale = _entranceController.isCompleted ? _pulseScaleAnimation.value : 1.0;

                return Opacity(
                  opacity: entranceOpacity,
                  child: Transform.translate(
                    offset: Offset(0, floatY),
                    child: Transform.rotate(
                      angle: entranceRot,
                      child: Transform.scale(
                        scale: entranceScale * pulseScale,
                        child: child,
                      ),
                    ),
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo container with animated glow and subtle ripple aura
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, logoChild) {
                      final glowRadius = _entranceController.isCompleted
                          ? _pulseGlowAnimation.value
                          : 28.0;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Concentric glowing ring aura
                          Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.secondaryGreen.withValues(
                                  alpha: _entranceController.isCompleted
                                      ? (_pulseController.value * 0.25 + 0.1)
                                      : 0.1,
                                ),
                                width: 2.0,
                              ),
                            ),
                          ),
                          // Main glowing avatar
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.secondaryGreen.withValues(alpha: 0.45),
                                  blurRadius: glowRadius,
                                  spreadRadius: 8,
                                ),
                                BoxShadow(
                                  color: const Color(0xFF52B788).withValues(alpha: 0.25),
                                  blurRadius: glowRadius * 1.5,
                                  spreadRadius: 14,
                                ),
                              ],
                            ),
                            child: logoChild,
                          ),
                        ],
                      );
                    },
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/fresh_cane_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.local_drink_rounded,
                          size: 76,
                          color: AppColors.secondaryLight,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Animated Title & Tagline
                  AnimatedBuilder(
                    animation: _entranceController,
                    builder: (context, _) {
                      return Transform.translate(
                        offset: Offset(0, _textSlideAnimation.value),
                        child: Opacity(
                          opacity: _opacityAnimation.value,
                          child: Column(
                            children: [
                              Text(
                                'FRESH CANE',
                                style: AppTextStyles.h1.copyWith(
                                  color: Colors.white,
                                  letterSpacing: 3.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'PURE · FRESH · HEALTHY',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.secondaryLight.withValues(alpha: 0.85),
                                  letterSpacing: 3.0,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 36),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.secondaryGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Role/Account Issues Alert Modal
          if (isNoticeState)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF142B20),
                  borderRadius: BorderRadius.circular(AppColors.radiusLarge),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.warning,
                        size: 44,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        authState.status == AuthStatus.missingProfile
                            ? 'Profile Not Found'
                            : (authState.status == AuthStatus.inactive
                                ? 'Account Suspended'
                                : 'Access Denied'),
                        style: AppTextStyles.h3.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        authState.errorMessage ??
                            'Please consult an administrator.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () =>
                            ref.read(authProvider.notifier).signOut(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
