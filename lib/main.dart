import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_model.dart';
import 'app/feedback.dart';
import 'app/services.dart';
import 'app/settings.dart';
import 'screens/root.dart';
import 'ui/doodle.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final feedback = GameFeedback(settings);
  await feedback.init();
  final model = AppModel(settings: settings, feedback: feedback);
  await model.start();
  unawaited(model.updates.check());
  runApp(PongApp(settings: settings, feedback: feedback, model: model));
}

/// テーマはスマホ版 PONG! と同じ（紙・墨・Yomogi）
class PongApp extends StatelessWidget {
  const PongApp({super.key, required this.settings, required this.feedback, required this.model, this.splash = true});

  final AppSettings settings;
  final GameFeedback feedback;
  final AppModel model;

  /// 起動時にロゴのスプラッシュを流すか（テストでは切る）
  final bool splash;

  @override
  Widget build(BuildContext context) {
    final text = ThemeData.light().textTheme.apply(fontFamily: kFontFamily, bodyColor: Palette.ink, displayColor: Palette.ink);
    return Services(
      settings: settings,
      feedback: feedback,
      model: model,
      child: MaterialApp(
        title: 'PONG!',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: kFontFamily,
          scaffoldBackgroundColor: Palette.paper,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Palette.ink,
            primary: Palette.ink,
            onPrimary: Palette.paper,
            surface: Palette.paper,
            onSurface: Palette.ink,
          ),
          textTheme: text.copyWith(
            titleLarge: text.titleLarge?.copyWith(fontSize: 24),
            bodyLarge: text.bodyLarge?.copyWith(fontSize: 18),
            bodyMedium: text.bodyMedium?.copyWith(fontSize: 16),
          ),
          textSelectionTheme: const TextSelectionThemeData(cursorColor: Palette.ink),
          sliderTheme: const SliderThemeData(activeTrackColor: Palette.ink, thumbColor: Palette.ink, inactiveTrackColor: Palette.faint),
        ),
        home: RootScreen(splash: splash),
      ),
    );
  }
}
