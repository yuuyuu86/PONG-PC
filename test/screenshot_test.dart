// 画面を PNG に書き出して見た目を確認する（任意）。
// SNAPSHOT_DIR=/path/to/dir flutter test test/screenshot_test.dart のときだけ動く。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pong_pc/app/app_model.dart';
import 'package:pong_pc/app/feedback.dart';
import 'package:pong_pc/app/settings.dart';
import 'package:pong_pc/games/core/catalog.dart';
import 'package:pong_pc/games/core/common.dart';
import 'package:pong_pc/games/core/match.dart';
import 'package:pong_pc/main.dart';
import 'package:pong_pc/net/wire.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final data = File(path).readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(data)))).load();
}

void main() {
  final dir = Platform.environment['SNAPSHOT_DIR'];

  testWidgets('画面を書き出す', (tester) async {
    await tester.runAsync(() async {
      await _loadFont('Yomogi', 'assets/fonts/Yomogi-Regular.ttf');
      final root = Platform.environment['FLUTTER_ROOT'] ?? '';
      final icons = '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
      if (File(icons).existsSync()) await _loadFont('MaterialIcons', icons);
    });
    SharedPreferences.setMockInitialValues({'playerName': 'ゆうた', 'avatar': '1.0.2.0', 'registered': true});
    final settings = await AppSettings.load();
    final model = AppModel(settings: settings, feedback: GameFeedback(settings));
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: PongApp(settings: settings, feedback: model.feedback, model: model)));

    Future<void> shot(String name) async {
      // 画面の切り替え（クロスフェード）が終わるまで進める
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage();
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot('01-home');
    model.go(Screen.setup, game: GameKind.badminton);
    await shot('02-setup');
    var info = const RoomInfo(code: 'KQTE', game: GameKind.volley, phase: RoomPhase.lobby, you: 0, players: [
      PlayerInfo(present: true, name: 'ゆうた', avatar: '1.0.2.0', connected: true),
      PlayerInfo.empty,
    ]);
    model.sessionRoom(info);
    await shot('03-room');
    for (final (i, game) in GameKind.values.indexed) {
      final e = MatchEngine(game, firstServer: 0);
      info = RoomInfo(code: 'KQTE', game: game, phase: RoomPhase.match, you: 0, players: [
        info.players[0],
        const PlayerInfo(present: true, name: 'はなこ', avatar: '2.1.4.0', connected: true),
      ]);
      model.sessionRoom(info);
      for (var t = 0; t < MatchEngine.introTime * 60 + 40; t++) {
        e.step([
          PlayerInput(right: t % 90 < 50, actPressed: t == 260, jump: game != GameKind.boxing && t == 255),
          PlayerInput(left: t % 70 < 30, actPressed: t == 275, jump: game == GameKind.boxing && t > 250),
        ], 1 / 60);
      }
      model.sessionState(e.state);
      await shot('1$i-match-${game.name}');
    }
    final over = MatchEngine(GameKind.volley, firstServer: 0);
    var serve = true;
    while (over.state.phase != MatchPhase.over) {
      over.step([PlayerInput(actPressed: over.state.phase == MatchPhase.play && serve), PlayerInput.none], 1 / 60);
      serve = !serve;
    }
    model.sessionState(over.state);
    model.sessionRoom(RoomInfo(code: 'KQTE', game: GameKind.volley, phase: RoomPhase.result, you: 0, players: [
      info.players[0],
      const PlayerInfo(present: true, name: 'はなこ', avatar: '2.1.4.0', connected: true, rematch: true),
    ]));
    await shot('20-result');
    model.go(Screen.settings);
    await shot('21-settings');
    model.keyboard.dispose();
  }, skip: dir == null);
}
