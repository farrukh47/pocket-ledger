import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/ledger_repository.dart';
import 'ui/home.dart';
import 'ui/splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const PocketLedgerApp());
}

class PocketLedgerApp extends StatefulWidget {
  const PocketLedgerApp({super.key});
  @override
  State<PocketLedgerApp> createState() => _PocketLedgerAppState();
}

class _PocketLedgerAppState extends State<PocketLedgerApp> {
  static const _seed = Color(0xFF0F766E);
  static const _surface = Color(0xFFF4F7F6);
  static const _ink = Color(0xFF14212B);
  static const _minSplash = Duration(milliseconds: 1800);

  late Future<_BootResult> _boot = _open();

  Future<_BootResult> _open() async {
    final started = DateTime.now();
    try {
      final repository = await LedgerRepository.open();
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minSplash) {
        await Future<void>.delayed(_minSplash - elapsed);
      }
      return _BootResult.ok(repository);
    } catch (_) {
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minSplash) {
        await Future<void>.delayed(_minSplash - elapsed);
      }
      return const _BootResult.failed();
    }
  }

  void _retry() => setState(() => _boot = _open());

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
      primary: _seed,
      surface: Colors.white,
    ).copyWith(
      onSurface: _ink,
      surfaceContainerHighest: const Color(0xFFE7EEEC),
      outlineVariant: const Color(0xFFD5E0DD),
    );

    return MaterialApp(
      title: 'Pocket Ledger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _surface,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: _surface,
          foregroundColor: _ink,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE2EAE7)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: _seed.withValues(alpha: 0.12),
          elevation: 0,
          height: 68,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _seed : const Color(0xFF6B7C78),
            );
          }),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _seed,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _seed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return _seed.withValues(alpha: 0.12);
              }
              return Colors.white;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return _seed;
              return const Color(0xFF5A6B67);
            }),
            side: WidgetStateProperty.all(
              const BorderSide(color: Color(0xFFD5E0DD)),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD5E0DD)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD5E0DD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _seed, width: 1.5),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE2EAE7),
          space: 28,
          thickness: 1,
        ),
      ),
      home: FutureBuilder<_BootResult>(
        future: _boot,
        builder: (context, state) {
          final result = state.data;
          final ready = result != null && result.repository != null;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: ready
                ? KeyedSubtree(
                    key: const ValueKey('home'),
                    child: Home(repository: result.repository!),
                  )
                : KeyedSubtree(
                    key: const ValueKey('splash'),
                    child: SplashScreen(
                      failed: result?.failed == true,
                      onRetry: result?.failed == true ? _retry : null,
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _BootResult {
  final LedgerRepository? repository;
  final bool failed;
  const _BootResult.ok(this.repository) : failed = false;
  const _BootResult.failed()
      : repository = null,
        failed = true;
}
