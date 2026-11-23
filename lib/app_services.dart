import 'dart:async';
import 'dart:io';

import 'package:basalt/basalt.dart';
import 'package:flutter/widgets.dart';

import 'data/db.dart';
import 'data/gym_repository.dart';
import 'domain/member_view.dart';
import 'services/app_lock.dart';
import 'services/backup_service.dart';
import 'services/prefs.dart';
import 'services/quick_access.dart';
import 'services/reminders.dart';

/// Everything the screens need, created once at start-up.
class AppServices {
  AppServices({required this.repo, required this.prefs, required this.backup, required this.reminders})
      : lock = AppLock(prefs) {
    _sub = repo.changes.listen((_) {
      unawaited(refreshGym().then((_) => _scheduleWidget()));
      _scheduleReminders();
    });
  }

  final GymRepository repo;
  final AppPrefs prefs;
  final AppLock lock;
  final BackupService backup;
  final ReminderService reminders;

  /// Gym name and currency, kept fresh for formatting.
  final gym = ValueNotifier(const GymInfo(name: 'My gym', currency: 'Rs', countryCode: '92'));

  /// Lets the Home tab open Members with a filter.
  final tabs = BTabController();
  final memberFilter = ValueNotifier(MemberFilter.all);

  StreamSubscription<void>? _sub;
  Timer? _debounce;

  static Future<AppServices> open() async {
    final prefs = await AppPrefs.load();
    final path = await AppDatabase.defaultPath();
    final repo = GymRepository(AppDatabase.openFile(File(path)));
    final services = AppServices(
      repo: repo,
      prefs: prefs,
      backup: BackupService(repo: repo, databasePath: path),
      reminders: ReminderService(repo: repo, prefs: prefs),
    );
    await services.refreshGym();
    QuickAccess.init();
    unawaited(QuickAccess.installShortcuts());
    unawaited(services.publishWidget());
    return services;
  }

  Future<void> refreshGym() async {
    try {
      gym.value = await repo.gymInfo();
    } catch (_) {
      // Keep the previous values; the next change retries.
    }
  }

  String money(double amount) => formatMoney(gym.value.currency, amount);

  Timer? _widgetDebounce;

  void _scheduleWidget() {
    _widgetDebounce?.cancel();
    _widgetDebounce = Timer(const Duration(seconds: 1), () => unawaited(publishWidget()));
  }

  /// Refreshes the home-screen widget: today's check-ins, fees due and overdue, money collected.
  Future<void> publishWidget() async {
    try {
      final now = DateTime.now();
      final views = [for (final m in await repo.members()) MemberView(m, now)];
      final checkins = await repo.checkinsOn(now);
      final paid = await repo.paymentsBetween(DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
      await QuickAccess.updateWidget(
        gym: gym.value.name,
        checkins: checkins.length,
        due: views.where((v) => v.isDueSoon).length,
        overdue: views.where((v) => v.isOverdue).length,
        revenue: '${money(paid.fold<double>(0, (a, p) => a + p.amount))} collected this month',
      );
    } catch (_) {
      // The widget is optional; the next change tries again.
    }
  }

  void _scheduleReminders() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(reminders.reschedule()));
  }

  /// Re-plans reminders now (app start, resume, settings change).
  Future<void> rescheduleReminders() => reminders.reschedule();

  Future<void> dispose() async {
    _debounce?.cancel();
    _widgetDebounce?.cancel();
    await _sub?.cancel();
    await repo.dispose();
    await repo.db.close();
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}

extension AppContext on BuildContext {
  AppServices get app => AppScope.of(this);
}
