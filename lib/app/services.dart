import 'package:flutter/widgets.dart';

import 'app_model.dart';
import 'feedback.dart';
import 'settings.dart';

/// アプリ全体で共有するサービス（設定・効果音・画面の流れ）。
class Services extends InheritedWidget {
  const Services({super.key, required this.settings, required this.feedback, required this.model, required super.child});

  final AppSettings settings;
  final GameFeedback feedback;
  final AppModel model;

  static Services of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Services>()!;

  @override
  bool updateShouldNotify(Services oldWidget) => settings != oldWidget.settings || feedback != oldWidget.feedback || model != oldWidget.model;
}
