import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/app.dart';
import 'package:gymdesk/app_services.dart';
import 'package:gymdesk/data/db.dart';
import 'package:gymdesk/data/gym_repository.dart';
import 'package:gymdesk/services/backup_service.dart';
import 'package:gymdesk/services/prefs.dart';
import 'package:gymdesk/services/reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppServices> _services() async {
  final prefs = await AppPrefs.load();
  final repo = GymRepository(AppDatabase.memory());
  return AppServices(
    repo: repo,
    prefs: prefs,
    backup: BackupService(repo: repo, databasePath: ':memory:'),
    reminders: ReminderService(repo: repo, prefs: prefs, platformEnabled: false),
  );
}

/// Pumps (letting real async work such as database queries finish) until [finder] matches.
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  testWidgets('first launch shows the introduction, then gym setup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final services = await tester.runAsync(_services);
    await tester.pumpWidget(GymdeskApp(boot: () async => services!));
    await pumpUntil(tester, find.text('Skip'));
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Your gym on your phone'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await pumpUntil(tester, find.text('Set up your gym'));
    expect(find.text('Set up your gym'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.runAsync(() => services!.dispose());
  });

  testWidgets('the app lock screen shows when a PIN is set', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true, 'pin.hash': 'x', 'pin.salt': 'y'});
    final services = await tester.runAsync(_services);
    await tester.pumpWidget(GymdeskApp(boot: () async => services!));
    await pumpUntil(tester, find.text('Enter PIN'));
    expect(find.text('Enter PIN'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    await tester.runAsync(() => services!.dispose());
  });
}
