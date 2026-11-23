import 'dart:io';

import 'package:basalt/basalt.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_services.dart';
import '../services/backup_service.dart';
import 'common.dart';

/// Asks for a password, writes an encrypted backup, then opens the share sheet so the owner can
/// keep a copy off the phone (Google Drive, WhatsApp to self, Files…).
Future<void> createBackupFlow(BuildContext context) async {
  final app = context.app;
  final password = await showSheet<String>(context, title: 'Back up now', builder: (_) => const _PasswordForm(confirm: true));
  if (password == null || !context.mounted) return;
  final file = await _withProgress(context, 'Creating backup…', () => app.backup.create(password));
  if (file == null || !context.mounted) return;
  await app.prefs.setLastBackupAt(DateTime.now());
  await app.rescheduleReminders();
  if (!context.mounted) return;
  BToast.show(context, 'Backup created. Save it somewhere safe.');
  await attempt(
    context,
    () => SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/octet-stream')], subject: 'Gymdesk backup'),
    ),
  );
}

/// Picks a backup file, asks for its password and replaces the data on this phone.
Future<void> restoreBackupFlow(BuildContext context) async {
  final app = context.app;
  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(type: FileType.any);
  } catch (e) {
    if (context.mounted) BToast.show(context, 'Could not open the file picker: $e');
    return;
  }
  final path = picked?.files.single.path;
  if (path == null || !context.mounted) return;
  final ok = await bConfirm(
    context,
    title: 'Replace data with this backup?',
    message: 'Everything currently in Gymdesk on this phone is replaced by the backup.',
    confirmLabel: 'Continue',
    danger: true,
  );
  if (!ok || !context.mounted) return;
  final password = await showSheet<String>(context, title: 'Backup password', builder: (_) => const _PasswordForm(confirm: false));
  if (password == null || !context.mounted) return;
  final done = await _withProgress(context, 'Restoring…', () async {
    await app.backup.restore(File(path), password);
    return true;
  });
  if (done == true && context.mounted) BToast.show(context, 'Backup restored');
}

Future<T?> _withProgress<T>(BuildContext context, String label, Future<T> Function() task) async {
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: Gap.lg),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  try {
    final result = await task();
    nav.pop();
    return result;
  } catch (e) {
    nav.pop();
    if (context.mounted) BToast.show(context, errorText(e));
    return null;
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({required this.confirm});

  final bool confirm;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;
  bool _show = false;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.confirm) {
      if (_a.text.length < BackupService.minPasswordLength) {
        setState(() => _error = 'Use at least ${BackupService.minPasswordLength} characters.');
        return;
      }
      if (_a.text != _b.text) {
        setState(() => _error = "The passwords don't match.");
        return;
      }
    } else if (_a.text.isEmpty) {
      setState(() => _error = 'Enter the backup password.');
      return;
    }
    Navigator.of(context).pop(_a.text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.basalt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.confirm)
          Text(
            'The backup is encrypted with this password. If you forget it, the backup cannot be opened; nobody can reset it.',
            style: BasaltType.body.copyWith(color: p.textMuted, fontSize: 14),
          ),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _a,
          autofocus: true,
          obscureText: !_show,
          decoration: InputDecoration(
            labelText: 'Backup password',
            suffixIcon: IconButton(
              tooltip: _show ? 'Hide password' : 'Show password',
              icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
          onSubmitted: (_) => widget.confirm ? null : _submit(),
        ),
        if (widget.confirm) ...[
          const SizedBox(height: Gap.md),
          TextField(
            controller: _b,
            obscureText: !_show,
            decoration: const InputDecoration(labelText: 'Confirm password'),
            onSubmitted: (_) => _submit(),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: Gap.sm),
          Text(_error!, style: BasaltType.caption.copyWith(color: p.danger)),
        ],
        const SizedBox(height: Gap.lg),
        BButton(label: widget.confirm ? 'Create backup' : 'Restore', onPressed: _submit, expand: true),
      ],
    );
  }
}
