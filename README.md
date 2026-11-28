# Gymdesk

*Renamed from **Mr. Gym** in 2.1.0. Your gym's own name is set inside the app.*

Offline gym management for one gym, on one Android phone. Part of the Basalt app suite.

Everything lives on the phone: no account, no server and no internet needed, except to open WhatsApp
or to download an app update from GitHub.


## What's new in 2.2

- **Appearance, your way:** Settings → Appearance. Theme (system, light, dark), 12 accent colours or any colour from the picker, background tone (neutral, warm, cool, tinted, pure black), font (Inter, Manrope, Space Grotesk, Lora or the system font), text size and bold text, density, corner shape, depth (flat, soft shadows or glass), navigation bar style and animations.
- **Live preview:** the screen redraws itself with your choices before you press Apply; Reset to default is one tap away. Custom colours are adjusted just enough to stay readable in both themes.

## What's new in 2.1

- **New name:** Mr. Gym is now **Gymdesk**, a name that fits any gym. Your own gym's name is still set inside the app and shown on every screen.
- **Expenses and profit:** log rent, electricity, salaries, equipment, maintenance and supplies. Analytics shows *profit this month* (fees collected minus expenses), with month-by-month browsing and a CSV export.
- **Home-screen widget:** today's check-ins, fees due this week and overdue, money collected this month, and a **Check in** button.
- **Shortcuts on the app icon:** long-press for *Mark attendance* and *Add member*.
## Features

- **Dashboard**: today's check-ins, fees due this week, overdue fees and revenue this month, with
  quick lists of who is overdue, who is due soon, birthdays this week and today's check-ins.
- **Mark attendance**: a front-desk screen to search a member and check them in with one tap (once per
  day, with undo). It warns when the member's fee is overdue or the membership is frozen.
- **Members**: a fast list with search by name or phone and filters (All, Active, Due, Overdue, Frozen,
  Inactive).
- **Member profile**: plan and fee, next due date, payment log, attendance history (visits this month,
  last visit, recent check-ins), notes, WhatsApp and call buttons.
- **Fees and payments**: "Record payment" for 1, 3, 6 or 12 months, starting from the due date or from
  today for someone returning after a long gap. Calendar months are used (31 Jan → 28 Feb → 31 Mar).
  The latest payment can be undone. Receipts can be sent over WhatsApp.
- **Membership plans**: Monthly, Quarterly, Half-yearly and Yearly are created from your monthly fee;
  add, edit or delete plans in Settings.
- **Freeze** a membership while a member is away: no fees are counted, and unfreezing moves the due date
  on by the frozen days. Members who leave can be marked inactive (history is kept) or deleted.
- **WhatsApp reminders**: prefilled fee reminders, receipts and birthday wishes (you press Send).
  Local numbers such as 0300 1234567 are converted with the country code set in Settings (default +92).
- **Daily notifications**: at a time you choose, a notification lists fees due today and overdue fees,
  plus a backup reminder when the last backup is over a week old. They are scheduled with Android's
  alarm service for the next 30 days, so they arrive even when the app is closed; they are re-planned
  whenever data changes or the app opens, and restored after a reboot.
- **Analytics**: revenue for the last 6 months, check-ins for the last 14 days, and member counts.
  Export members or payments as CSV through the share sheet.
- **Optional PIN lock** (off by default): 4–8 digits, locks again after a chosen time in the
  background, with increasing waits after wrong attempts.
- **Encrypted backups**: a consistent snapshot of the database encrypted with AES-256-GCM and a
  password you choose (PBKDF2-SHA256), shared to Drive, WhatsApp or Files. Restoring checks the file
  first and leaves your data untouched if anything fails. Backups from Mr. Gym 1.x can be restored.
- Light, dark or system theme.

The database itself is a normal SQLite file inside the app's private storage (it is not encrypted on
the phone); backups are always encrypted.

## Stack

Flutter, Drift (SQLite), the shared `basalt` package (design system and updater),
flutter_local_notifications, share_plus, file_picker and url_launcher.

## Updates

The app checks this repository's GitHub Releases each time it opens (and again after 15 minutes in the
background). When a newer version exists it offers to download the APK for the phone's processor,
verifies its size and SHA-256, and opens Android's installer. Settings → Updates checks on demand.

## Build

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift code generation
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

CI (`.github/workflows/build.yml`) runs analysis and tests, builds the APKs, and runs an emulator smoke
test with end-to-end checks (`scripts/smoke.sh`, `scripts/e2e.sh`). Tagged builds are signed with the
suite's release key from repository secrets and published as a GitHub Release.

Package name: `dev.basalt.mrgym`. Version 2.0 uses a new package name, so it installs next to 1.x; move
your data across with a 1.x encrypted backup and "Restore from a backup".
