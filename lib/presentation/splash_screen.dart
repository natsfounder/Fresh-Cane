import 'package:flutter/material.dart';
import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
import '../services/supabase_service.dart';

/// Foundation initial screen verifying environment & build readiness.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isReady = false;
  String _statusMessage = 'Initializing Fresh Cane POS...';

  @override
  void initState() {
    super.initState();
    _checkReadiness();
  }

  Future<void> _checkReadiness() async {
    try {
      final isAuth = SupabaseService.isAuthenticated;

      setState(() {
        _isReady = true;
        _statusMessage = isAuth
            ? 'Connected • Authenticated'
            : 'Connected • Ready for Login (${AppConfig.supabaseUrl})';
      });
    } catch (e) {
      setState(() {
        _isReady = false;
        _statusMessage = 'Initialization Notice: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_drink_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  AppConfig.appName,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pure & Natural Sugarcane Juice • POS v${AppConfig.appVersion}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                if (!_isReady)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: AppTheme.accentLime,
                      strokeWidth: 2.5,
                    ),
                  )
                else
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.accentLime,
                    size: 28,
                  ),
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
