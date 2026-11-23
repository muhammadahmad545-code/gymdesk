import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../services/app_lock.dart';

/// Number pad with dots. [onSubmit] returns an error message, or null when accepted.
class PinEntry extends StatefulWidget {
  const PinEntry({
    super.key,
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.onSubmit,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final String actionLabel;
  final Future<String?> Function(String pin) onSubmit;
  final Widget? footer;

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  void _tap(String d) {
    if (_busy || _pin.length >= AppLock.maxLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_pin.length < AppLock.minLength) {
      setState(() => _error = 'Enter at least ${AppLock.minLength} digits.');
      return;
    }
    setState(() => _busy = true);
    final error = await widget.onSubmit(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error != null) {
        _error = error;
        _pin = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.basalt;
    Widget key(String label, {VoidCallback? onTap, IconData? icon, String? semantics}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xs),
          child: Semantics(
            label: semantics ?? label,
            button: true,
            excludeSemantics: true,
            child: Material(
              color: icon == null ? p.surface : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.lg),
                side: BorderSide(color: icon == null ? p.border : Colors.transparent),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.lg),
                onTap: onTap,
                child: SizedBox(
                  height: 60,
                  child: Center(
                    child: icon != null
                        ? Icon(icon, color: p.textMuted)
                        : Text(label, style: BasaltType.title.copyWith(color: p.text)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget row(List<String> digits) => Row(children: [for (final d in digits) key(d, onTap: () => _tap(d))]);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - Gap.lg * 2),
            child: IntrinsicHeight(
              child: Column(
          children: [
            const Spacer(),
            const BIconTile(Icons.lock_outline_rounded, size: 56),
            const SizedBox(height: Gap.lg),
            Text(widget.title, textAlign: TextAlign.center, style: BasaltType.title.copyWith(color: p.text)),
            if (widget.subtitle != null) ...[
              const SizedBox(height: Gap.xs),
              Text(widget.subtitle!, textAlign: TextAlign.center, style: BasaltType.body.copyWith(color: p.textMuted)),
            ],
            const SizedBox(height: Gap.xl),
            Semantics(
              label: '${_pin.length} digits entered',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < (_pin.length < AppLock.minLength ? AppLock.minLength : _pin.length); i++)
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? p.accent : Colors.transparent,
                        border: Border.all(color: i < _pin.length ? p.accent : p.border, width: 1.5),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 36,
              child: Center(
                child: Text(_error ?? '', textAlign: TextAlign.center, style: BasaltType.caption.copyWith(color: p.danger)),
              ),
            ),
            const Spacer(),
            row(['1', '2', '3']),
            row(['4', '5', '6']),
            row(['7', '8', '9']),
            Row(
              children: [
                const Expanded(child: SizedBox()),
                key('0', onTap: () => _tap('0')),
                key('', icon: Icons.backspace_outlined, semantics: 'Delete digit', onTap: _back),
              ],
            ),
            const SizedBox(height: Gap.md),
            BButton(label: widget.actionLabel, onPressed: _submit, busy: _busy, expand: true),
            if (widget.footer != null) ...[const SizedBox(height: Gap.xs), widget.footer!],
          ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  Future<void> _forgot(BuildContext context) async {
    final app = context.app;
    final ok = await bConfirm(
      context,
      title: 'Forgot your PIN?',
      message: 'The only way back in is to erase all Gymdesk data on this phone. '
          'You can then restore an encrypted backup if you made one.',
      confirmLabel: 'Erase all data',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final sure = await bConfirm(
      context,
      title: 'Erase everything?',
      message: 'Members, payments and attendance on this phone will be deleted. This cannot be undone.',
      confirmLabel: 'Erase',
      danger: true,
    );
    if (!sure) return;
    await app.repo.eraseAll();
    await app.prefs.clearAll();
    await app.lock.disable();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      body: PinEntry(
        title: 'Enter PIN',
        subtitle: app.gym.value.name,
        actionLabel: 'Unlock',
        onSubmit: (pin) => app.lock.check(pin),
        footer: BButton(label: 'Forgot PIN?', variant: BButtonVariant.ghost, onPressed: () => _forgot(context)),
      ),
    );
  }
}

/// Choose and confirm a new PIN. Pops true when the PIN is saved.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  String? _first;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: _first == null
          ? PinEntry(
              key: const ValueKey('first'),
              title: 'Choose a PIN',
              subtitle: 'Use ${AppLock.minLength} to ${AppLock.maxLength} digits.',
              actionLabel: 'Next',
              onSubmit: (pin) async {
                final error = AppLock.validate(pin);
                if (error != null) return error;
                setState(() => _first = pin);
                return null;
              },
            )
          : PinEntry(
              key: const ValueKey('confirm'),
              title: 'Confirm your PIN',
              subtitle: 'Enter the same PIN again.',
              actionLabel: 'Save PIN',
              onSubmit: (pin) async {
                if (pin != _first) {
                  BToast.show(context, "The PINs didn't match. Choose your PIN again.");
                  setState(() => _first = null);
                  return "The PINs didn't match. Start again.";
                }
                await app.lock.enable(pin);
                if (context.mounted) Navigator.of(context).pop(true);
                return null;
              },
            ),
    );
  }
}

/// Asks for the current PIN. Pops true when it is correct.
class VerifyPinScreen extends StatelessWidget {
  const VerifyPinScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PinEntry(
        title: 'Enter your current PIN',
        actionLabel: 'Continue',
        onSubmit: (pin) async {
          final error = await app.lock.check(pin, unlockOnSuccess: false);
          if (error == null && context.mounted) Navigator.of(context).pop(true);
          return error;
        },
      ),
    );
  }
}
