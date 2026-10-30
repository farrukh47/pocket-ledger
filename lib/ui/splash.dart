import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Branded loading screen shown while the ledger database opens.
class SplashScreen extends StatelessWidget {
  final bool failed;
  final VoidCallback? onRetry;

  const SplashScreen({super.key, this.failed = false, this.onRetry});

  static const _teal = Color(0xFF0F766E);
  static const _deep = Color(0xFF0B2530);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _deep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_teal, Color(0xFF134E4A), _deep],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 44,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Pocket Ledger',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  failed ? 'Could not open your ledger' : 'Opening your account…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 14,
                  ),
                ),
                const Spacer(flex: 2),
                if (failed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 36),
                    child: Column(
                      children: [
                        Text(
                          'Your data has not been cleared.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: onRetry,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _teal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
