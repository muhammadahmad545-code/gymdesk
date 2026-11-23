import 'dart:async';

import 'package:basalt/basalt.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore opens the backup on its own connection before swapping it in.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  unawaited(BasaltUpdater.instance.start(owner: 'muhammadahmad545-code', repo: 'gymdesk'));
  runApp(const GymdeskApp());
}
