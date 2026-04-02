import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:desktop/screens/splash_screen.dart';
import 'package:desktop/providers/server_process_provider.dart';
import 'package:desktop/providers/theme_mode_provider.dart';
import 'package:desktop/theme/app_theme.dart';

void main() {
  // Initialize sqflite for desktop
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const ProviderScope(child: LynSokDesktopApp()));
}

class LynSokDesktopApp extends ConsumerStatefulWidget {
  const LynSokDesktopApp({super.key});

  @override
  ConsumerState<LynSokDesktopApp> createState() => _LynSokDesktopAppState();
}

class _LynSokDesktopAppState extends ConsumerState<LynSokDesktopApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ref.read(serverServiceProvider).stopAll());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(ref.read(serverServiceProvider).stopAll());
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'LynSok',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
