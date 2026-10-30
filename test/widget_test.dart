import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pong_pc/app/app_model.dart';
import 'package:pong_pc/app/feedback.dart';
import 'package:pong_pc/app/settings.dart';
import 'package:pong_pc/games/core/catalog.dart';
import 'package:pong_pc/main.dart';
import 'package:pong_pc/net/wire.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('共通ボタンをキーボードで実行できる', (tester) async {
    SharedPreferences.setMockInitialValues({'playerName': 'ゆうた', 'registered': true, 'soundOn': false});
    final settings = await AppSettings.load();
    final model = AppModel(settings: settings, feedback: GameFeedback(settings));
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(model.keyboard.dispose);
    await tester.pumpWidget(PongApp(settings: settings, feedback: model.feedback, model: model));
    Focus.of(tester.element(find.text('あそびかた'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 300));
    expect(model.screen, Screen.howto);
  });

  testWidgets('部屋の画面は、相手が参加すると表示が変わる', (tester) async {
    SharedPreferences.setMockInitialValues({'playerName': 'ゆうた', 'avatar': '0.0.1.0', 'registered': true});
    final settings = await AppSettings.load();
    final model = AppModel(settings: settings, feedback: GameFeedback(settings));
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PongApp(settings: settings, feedback: model.feedback, model: model));

    const me = PlayerInfo(present: true, name: 'ゆうた', connected: true);
    model.sessionRoom(const RoomInfo(code: 'KQTE', game: GameKind.volley, phase: RoomPhase.lobby, you: 0, players: [me, PlayerInfo.empty]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('紙飛行機で招待'), findsOneWidget);
    expect(find.textContaining('まだいません'), findsOneWidget);

    model.sessionRoom(const RoomInfo(code: 'KQTE', game: GameKind.volley, phase: RoomPhase.lobby, you: 0, players: [
      me,
      PlayerInfo(present: true, name: 'はなこ', connected: true),
    ]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('はなこ'), findsOneWidget);
    expect(find.text('紙飛行機で招待'), findsNothing, reason: '相手がそろったら招待の欄は消える');
    expect(find.textContaining('「準備OK」を押してください'), findsOneWidget);
    model.keyboard.dispose();
  });

  testWidgets('ホームの札から部屋づくり・参加へ進み、あそびかたはタブで切り替える', (tester) async {
    SharedPreferences.setMockInitialValues({'playerName': 'ゆうた', 'registered': true, 'soundOn': false});
    final settings = await AppSettings.load();
    final model = AppModel(settings: settings, feedback: GameFeedback(settings));
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(model.keyboard.dispose);
    await tester.pumpWidget(PongApp(settings: settings, feedback: model.feedback, model: model));

    // ホーム: 左の札から「部屋を作る」は競技えらび、「コードで参加」はコード入力へ
    await tester.tap(find.text('部屋を作る'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(model.screen, Screen.create);
    expect(find.text('バレー'), findsOneWidget);
    model.go(Screen.home);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('コードで参加'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(model.screen, Screen.join);
    expect(find.byType(TextField), findsOneWidget);

    // あそびかた: 「はじめかた」と競技ごとのタブ
    model.go(Screen.howto);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('同じWi-Fiにつなぎ'), findsOneWidget);
    await tester.tap(find.text('バレー'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('真上にトス'), findsOneWidget);
    expect(find.textContaining('同じWi-Fiにつなぎ'), findsNothing);
  });
}
