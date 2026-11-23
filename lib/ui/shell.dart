import 'dart:async';

import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../services/quick_access.dart';
import 'analytics_screen.dart';
import 'check_in_screen.dart';
import 'home_screen.dart';
import 'member_editor_screen.dart';
import 'members_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _askedPermission = false;
  StreamSubscription<String>? _actions;

  @override
  void initState() {
    super.initState();
    // Launcher shortcuts and the widget's Check in button.
    _actions = QuickAccess.actions.listen((a) {
      QuickAccess.consumed();
      _open(a);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final a = await QuickAccess.takeAction();
      if (a != null) _open(a);
    });
  }

  @override
  void dispose() {
    _actions?.cancel();
    super.dispose();
  }

  void _open(String action) {
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    switch (action) {
      case 'checkin':
        nav.push(MaterialPageRoute<void>(builder: (_) => const CheckInScreen()));
      case 'add-member':
        nav.push(MaterialPageRoute<void>(builder: (_) => const MemberEditorScreen()));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_askedPermission) {
      _askedPermission = true;
      final app = context.app;
      // Reminders are on by default; Android 13+ needs the user's permission to show them.
      if (app.prefs.feeReminders || app.prefs.backupReminders) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await app.reminders.requestPermission();
          await app.rescheduleReminders();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BTabShell(
      controller: context.app.tabs,
      tabs: [
        BTab(label: 'Home', icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard_rounded, builder: (_) => const HomeScreen()),
        BTab(label: 'Members', icon: Icons.people_outline_rounded, selectedIcon: Icons.people_rounded, builder: (_) => const MembersScreen()),
        BTab(label: 'Analytics', icon: Icons.bar_chart_rounded, builder: (_) => const AnalyticsScreen()),
        BTab(label: 'Settings', icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, builder: (_) => const SettingsScreen()),
      ],
    );
  }
}
