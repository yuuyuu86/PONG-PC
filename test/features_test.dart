import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pong_pc/app/app_model.dart';
import 'package:pong_pc/app/feedback.dart';
import 'package:pong_pc/app/keyboard.dart';
import 'package:pong_pc/app/records.dart';
import 'package:pong_pc/app/settings.dart';
import 'package:pong_pc/games/boxing/boxing.dart';
import 'package:pong_pc/games/core/catalog.dart';
import 'package:pong_pc/games/core/match.dart';
import 'package:pong_pc/net/wire.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('部屋のルール: 何点先取とボクシングの試合時間が試合に反映される', () {
    expect(MatchEngine(GameKind.volley, rule: 3).winScore, 3);
    expect(MatchEngine(GameKind.volley).winScore, 5);
    final box = MatchEngine(GameKind.boxing, rule: 30);
    expect((box.state.world as BoxingWorld).clock, 30);
    expect(GameKind.volley.ruleTextFor(7), startsWith('先に7点'));
    final info = RoomInfo.fromJson(const RoomInfo(code: 'ABCD', game: GameKind.fencing, phase: RoomPhase.lobby, you: 0, players: [PlayerInfo.empty, PlayerInfo.empty], rule: 11).toJson());
    expect(info.ruleValue, 11);
  });

  test('キーの割り当て: 変えたキーで動き、重なったキーは入れ替わる', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    s.bindKey(GameAction.left, PhysicalKeyboardKey.arrowLeft, '←');
    expect(s.keys[GameAction.left], PhysicalKeyboardKey.arrowLeft);
    expect(s.keys.describe('A / D'), '← / D');
    // ジャンプに D を割り当てると、右は Space になる
    s.bindKey(GameAction.jump, PhysicalKeyboardKey.keyD, 'D');
    expect(s.keys[GameAction.right], PhysicalKeyboardKey.space);
    s.resetKeys();
    expect(s.keys.isStandard, isTrue);
  });

  test('対戦結果: 試合が終わると1回だけ記録される', () async {
    SharedPreferences.setMockInitialValues({'playerName': 'ゆうた', 'registered': true, 'soundOn': false});
    final s = await AppSettings.load();
    final model = AppModel(settings: s, feedback: GameFeedback(s));
    addTearDown(model.keyboard.dispose);
    model.sessionRoom(const RoomInfo(code: 'ABCD', game: GameKind.badminton, phase: RoomPhase.match, you: 1, rule: 7, players: [
      PlayerInfo(present: true, name: 'はなこ', avatar: '0.0.0.0', connected: true),
      PlayerInfo(present: true, name: 'ゆうた', connected: true),
    ]));
    final over = MatchEngine(GameKind.badminton).state
      ..phase = MatchPhase.over
      ..score = [3, 7]
      ..winner = 1;
    model.sessionState(over);
    model.sessionState(over);
    final r = s.records;
    expect(r, hasLength(1));
    expect(r.single.won, isTrue);
    expect((r.single.myScore, r.single.opponentScore, r.single.opponent, r.single.rule), (7, 3, 'はなこ', 7));
  });

  test('対戦結果: 壊れた記録が混ざっていても、ほかの記録は読める', () {
    const good = {'at': 1, 'g': 'volley', 'r': 5, 'o': 'はなこ', 'oa': '', 'm': 5, 'os': 2, 'w': true};
    final list = MatchRecord.decodeList(jsonEncode([good, {'g': 'volley'}, 'x', {'at': 'bad', 'g': 'volley'}, good]));
    expect(list, hasLength(2));
  });
}
