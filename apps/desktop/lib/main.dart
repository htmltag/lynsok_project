import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:desktop/screens/splash_screen.dart';
import 'package:desktop/providers/theme_mode_provider.dart';
import 'package:desktop/theme/app_theme.dart';

void main() {
  // Initialize sqflite for desktop
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const ProviderScope(child: LynSokDesktopApp()));
}

class LynSokDesktopApp extends ConsumerWidget {
  const LynSokDesktopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'LynSøk Desktop',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
