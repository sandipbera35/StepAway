import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import 'native.dart';
import 'shell.dart';
import 'strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerExtraLicenses({'ZXing (QR scanning)': 'assets/android_licenses.txt'});
  final native = MethodChannelNative();
  final theme = ThemeController(store: NativeThemeStore(native));
  await theme.init();
  runApp(StepAwayApp(native: native, theme: theme));
}

class StepAwayApp extends StatefulWidget {
  const StepAwayApp({super.key, required this.native, this.theme, this.clock});
  final DateTime Function()? clock;
  final Native native;
  final ThemeController? theme;

  @override
  State<StepAwayApp> createState() => _StepAwayAppState();
}

class _StepAwayAppState extends State<StepAwayApp> {
  late final ThemeController _theme = widget.theme ?? ThemeController();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => MaterialApp(
        title: S.appName,
        debugShowCheckedModeBanner: false,
        theme: StepAwayTheme.light(),
        darkTheme: StepAwayTheme.dark(),
        themeMode: _theme.mode,
        scrollBehavior: const NoScrollbarBehavior(),
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              statusBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: GlassBackground(child: child ?? const SizedBox.shrink()),
          );
        },
        home: HomeShell(
          native: widget.native,
          theme: _theme,
          clock: widget.clock,
        ),
      ),
    );
  }
}
