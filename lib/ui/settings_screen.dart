import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../app_services.dart';
import '../data/gym_repository.dart';
import 'backup_screen.dart';
import 'common.dart';
import 'expenses_screen.dart';
import 'pin_screens.dart';
import 'plans_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.prefs, app.gym, app.lock]),
      builder: (context, _) {
        final p = context.basalt;
        final prefs = app.prefs;
        final gym = app.gym.value;
        final last = prefs.lastBackupAt;
        return BPage(
          title: 'Settings',
          children: [
            BGroup(
              title: 'Gym',
              children: [
                BListRow(
                  icon: Icons.storefront_outlined,
                  title: 'Gym name',
                  subtitle: gym.name,
                  chevron: true,
                  onTap: () => _editText(context, 'Gym name', gym.name, (v) => app.repo.updateGym(name: v)),
                ),
                BListRow(
                  icon: Icons.payments_outlined,
                  title: 'Currency',
                  subtitle: gym.currency.isEmpty ? 'None' : gym.currency,
                  chevron: true,
                  onTap: () => _editText(context, 'Currency symbol', gym.currency, (v) => app.repo.updateGym(currency: v)),
                ),
                BListRow(
                  icon: Icons.chat_outlined,
                  title: 'WhatsApp country code',
                  subtitle: '+${gym.countryCode} · numbers like 0300… become +${gym.countryCode} 300…',
                  chevron: true,
                  onTap: () => _editText(
                    context,
                    'Country code',
                    gym.countryCode,
                    (v) => app.repo.updateGym(countryCode: v),
                    number: true,
                  ),
                ),
                BListRow(
                  icon: Icons.sell_outlined,
                  title: 'Membership plans',
                  subtitle: 'Fees and lengths',
                  chevron: true,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlansScreen())),
                ),
              ],
            ),
            BGroup(
              title: 'Reminders',
              children: [
                BListRow(
                  icon: Icons.notifications_none_rounded,
                  title: 'Fee reminders',
                  subtitle: 'A daily notification when fees are due or overdue',
                  onTap: () => _setFees(app, !prefs.feeReminders),
                  trailing: Switch(value: prefs.feeReminders, onChanged: (v) => _setFees(app, v)),
                ),
                BListRow(
                  icon: Icons.backup_outlined,
                  title: 'Backup reminders',
                  subtitle: 'When the last backup is over ${prefs.backupEveryDays} days old',
                  onTap: () => _setBackups(app, !prefs.backupReminders),
                  trailing: Switch(value: prefs.backupReminders, onChanged: (v) => _setBackups(app, v)),
                ),
                BListRow(
                  icon: Icons.schedule_rounded,
                  title: 'Reminder time',
                  subtitle: prefs.reminderTime.format(context),
                  chevron: true,
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: prefs.reminderTime, helpText: 'Daily reminder time');
                    if (t == null) return;
                    await prefs.setReminderTime(t);
                    await app.rescheduleReminders();
                  },
                ),
              ],
            ),
            BGroup(
              title: 'Money',
              children: [
                BListRow(
                  icon: Icons.receipt_long_outlined,
                  title: 'Expenses',
                  subtitle: 'Rent, salaries, electricity… and the profit left over',
                  chevron: true,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ExpensesScreen())),
                ),
              ],
            ),
            const BGroup(
              title: 'Quick access',
              children: [
                BListRow(
                  icon: Icons.widgets_outlined,
                  title: 'Home-screen widget',
                  subtitle: 'Long-press your home screen → Widgets → Gymdesk. Shows today\'s check-ins, fees due and overdue, with a Check in button.',
                  maxSubtitleLines: 3,
                ),
                BListRow(
                  icon: Icons.apps_rounded,
                  title: 'Shortcuts on the app icon',
                  subtitle: 'Long-press Gymdesk for Mark attendance and Add member.',
                ),
              ],
            ),
            BGroup(
              title: 'Security',
              children: [
                BListRow(
                  icon: Icons.lock_outline_rounded,
                  title: 'App lock',
                  subtitle: app.lock.enabled ? 'A PIN is needed to open Gymdesk' : 'Off',
                  onTap: () => _toggleLock(context, !app.lock.enabled),
                  trailing: Switch(value: app.lock.enabled, onChanged: (v) => _toggleLock(context, v)),
                ),
                if (app.lock.enabled) ...[
                  BListRow(
                    icon: Icons.password_rounded,
                    title: 'Change PIN',
                    chevron: true,
                    onTap: () async {
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const VerifyPinScreen(title: 'Change PIN')),
                      );
                      if (ok != true || !context.mounted) return;
                      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SetPinScreen()));
                      if (saved == true && context.mounted) BToast.show(context, 'PIN changed');
                    },
                  ),
                  BListRow(
                    icon: Icons.timer_outlined,
                    title: 'Lock after',
                    subtitle: _lockLabel(prefs.autoLockMinutes),
                    chevron: true,
                    onTap: () => _pickAutoLock(context),
                  ),
                ],
              ],
            ),
            BGroup(
              title: 'Backup',
              children: [
                BListRow(
                  icon: Icons.backup_outlined,
                  title: 'Back up now',
                  subtitle: last == null ? 'No backup yet' : 'Last backup ${DateFormat('d MMM yyyy, h:mm a').format(last)}',
                  chevron: true,
                  onTap: () => createBackupFlow(context),
                ),
                BListRow(
                  icon: Icons.settings_backup_restore_rounded,
                  title: 'Restore from backup',
                  subtitle: 'Replace the data on this phone with a backup file',
                  chevron: true,
                  onTap: () => restoreBackupFlow(context),
                ),
              ],
            ),
            BGroup(
              title: 'Appearance',
              children: [
                BListRow(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: '${switch (prefs.themeMode) { ThemeMode.light => 'Light', ThemeMode.dark => 'Dark', _ => 'System' }} theme · colour, font, text size, layout and motion',
                  chevron: true,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => BasaltAppearanceScreen(
                      appName: 'Gymdesk',
                      appAccent: appAccent,
                      themeMode: prefs.themeMode,
                      onThemeMode: prefs.setThemeMode,
                    ),
                  )),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            const UpdatesSection(),
            BGroup(
              title: 'Data',
              children: [
                BListRow(
                  icon: Icons.delete_forever_outlined,
                  title: 'Erase all data',
                  subtitle: 'Delete every member, payment and check-in on this phone',
                  danger: true,
                  onTap: () => _erase(context),
                ),
              ],
            ),
            const SizedBox(height: Gap.xl),
            Center(
              child: Text(
                'Gymdesk · works offline · your data stays on this phone',
                textAlign: TextAlign.center,
                style: BasaltType.caption.copyWith(color: p.textFaint),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _setFees(AppServices app, bool on) async {
    if (on) await app.reminders.requestPermission();
    await app.prefs.setFeeReminders(on);
    await app.rescheduleReminders();
  }

  static Future<void> _setBackups(AppServices app, bool on) async {
    if (on) await app.reminders.requestPermission();
    await app.prefs.setBackupReminders(on);
    await app.rescheduleReminders();
  }

  static String _lockLabel(int minutes) => switch (minutes) {
        0 => 'Immediately',
        1 => '1 minute in the background',
        _ => '$minutes minutes in the background',
      };

  Future<void> _pickAutoLock(BuildContext context) async {
    final app = context.app;
    final picked = await showSheet<int>(
      context,
      title: 'Lock after',
      builder: (ctx) => Column(
        children: [
          for (final m in const [0, 1, 5, 15])
            BListRow(
              title: _lockLabel(m),
              trailing: app.prefs.autoLockMinutes == m ? Icon(Icons.check_rounded, color: ctx.basalt.accent) : null,
              onTap: () => Navigator.pop(ctx, m),
            ),
        ],
      ),
    );
    if (picked != null) await app.prefs.setAutoLockMinutes(picked);
  }

  Future<void> _toggleLock(BuildContext context, bool on) async {
    final app = context.app;
    if (on) {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SetPinScreen()));
      if (saved == true && context.mounted) BToast.show(context, 'App lock is on');
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const VerifyPinScreen(title: 'Turn off app lock')),
    );
    if (ok == true) {
      await app.lock.disable();
      if (context.mounted) BToast.show(context, 'App lock is off');
    }
  }

  Future<void> _editText(
    BuildContext context,
    String label,
    String initial,
    Future<void> Function(String) save, {
    bool number = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showSheet<String>(
      context,
      title: label,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          const SizedBox(height: Gap.lg),
          BButton(label: 'Save', expand: true, onPressed: () => Navigator.pop(ctx, controller.text)),
        ],
      ),
    );
    if (value == null || !context.mounted) return;
    await attempt(context, () => save(value));
  }

  Future<void> _erase(BuildContext context) async {
    final app = context.app;
    final ok = await bConfirm(
      context,
      title: 'Erase all data?',
      message: 'Every member, payment and check-in on this phone is deleted. Make a backup first if you might need it. This cannot be undone.',
      confirmLabel: 'Erase everything',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final sure = await bConfirm(context, title: 'Are you sure?', confirmLabel: 'Yes, erase', danger: true);
    if (!sure) return;
    try {
      await app.repo.eraseAll();
      await app.lock.disable();
    } on AppError catch (e) {
      if (context.mounted) BToast.show(context, e.message);
    }
  }
}
