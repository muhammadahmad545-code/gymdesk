import 'dart:async';

import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';

import 'app_services.dart';
import 'ui/common.dart';
import 'ui/gym_setup_screen.dart';
import 'ui/pin_screens.dart';
import 'ui/shell.dart';

const appAccent = BasaltAccent.lime;

class GymdeskApp extends StatefulWidget {
  const GymdeskApp({super.key, this.boot});

  /// Builds the services; tests pass an in-memory version.
  final Future<AppServices> Function()? boot;

  @override
  State<GymdeskApp> createState() => _GymdeskAppState();
}

class _GymdeskAppState extends State<GymdeskApp> with WidgetsBindingObserver {
  AppServices? _services;
  BasaltAppearanceController? _appearance;
  Object? _error;
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _error = null);
    try {
      final s = await (widget.boot ?? AppServices.open)().timeout(const Duration(seconds: 20));
      final look = _appearance ?? await BasaltAppearanceController.load();
      if (_appearance == null) look.addListener(_changed);
      _appearance = look;
      s.prefs.addListener(_changed);
      s.lock.addListener(_lockChanged);
      if (!mounted) return;
      setState(() => _services = s);
      unawaited(s.rescheduleReminders());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Locking closes any open screens, sheets and dialogs so nothing shows above the lock screen.
  void _lockChanged() {
    if (_services?.lock.locked ?? false) _navigator.currentState?.popUntil((r) => r.isFirst);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _services?.prefs.removeListener(_changed);
    _appearance?.removeListener(_changed);
    _services?.lock.removeListener(_lockChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = _services;
    if (s == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        s.lock.onBackground();
      case AppLifecycleState.resumed:
        s.lock.onForeground();
        unawaited(s.rescheduleReminders());
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _services;
    final look = _appearance;
    Widget home;
    if (_error != null) {
      home = _BootError(error: _error!, onRetry: _boot);
    } else if (s == null) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else {
      home = const Gate();
    }
    return MaterialApp(
      title: 'Gymdesk',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: basaltTheme(Brightness.light, appAccent, appearance: look?.value ?? BasaltAppearance.defaults, reduceMotion: look?.reduceMotion ?? false),
      darkTheme: basaltTheme(Brightness.dark, appAccent, appearance: look?.value ?? BasaltAppearance.defaults, reduceMotion: look?.reduceMotion ?? false),
      themeMode: s?.prefs.themeMode ?? ThemeMode.system,
      builder: (context, child) {
        final body = s == null ? child! : AppScope(services: s, child: child!);
        return look == null ? body : look.wrap(context, body);
      },
      home: home,
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: BEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Gymdesk could not start',
            message: errorText(error),
            actionLabel: 'Try again',
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}

/// Lock → introduction → gym setup → tabs.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool? _setUp;
  Object? _error;
  StreamSubscription<void>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null) {
      _sub = context.app.repo.changes.listen((_) => _check());
      _check();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final v = await context.app.repo.isSetUp();
      if (!mounted) return;
      setState(() {
        _setUp = v;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.prefs, app.lock]),
      builder: (context, _) {
        if (app.lock.locked) return const LockScreen();
        if (!app.prefs.onboarded) {
          return BOnboarding(
            appName: 'Gymdesk',
            pages: const [
              BOnboardingPage(
                icon: Icons.fitness_center_rounded,
                title: 'Your gym on your phone',
                body: 'Members, attendance and fees in one place. Everything stays on this phone, with no account and no internet needed.',
              ),
              BOnboardingPage(
                icon: Icons.payments_outlined,
                title: 'Never miss a fee',
                body: 'See who is due and overdue, record payments, and send reminders and receipts over WhatsApp.',
              ),
              BOnboardingPage(
                icon: Icons.lock_outline_rounded,
                title: 'Private and backed up',
                body: 'Daily reminders arrive even when the app is closed. Add a PIN lock and make encrypted backups in Settings.',
              ),
            ],
            onDone: () => app.prefs.setOnboarded(),
          );
        }
        if (_error != null) return _BootError(error: _error!, onRetry: _check);
        if (_setUp == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (_setUp == false) return GymSetupScreen(onDone: _check);
        return const HomeShell();
      },
    );
  }
}
