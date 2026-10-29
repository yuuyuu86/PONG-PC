import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pong_pc/games/boxing/boxing.dart';
import 'package:pong_pc/games/core/catalog.dart';
import 'package:pong_pc/games/core/common.dart';
import 'package:pong_pc/games/core/match.dart';
import 'package:pong_pc/games/fencing/fencing.dart';
import 'package:pong_pc/games/rally/rally.dart';
import 'package:pong_pc/net/wire.dart';

/// 簡単なボット。押した瞬間は前のフレームとの差で作る（実際の入力と同じ形）
class Bot {
  Bot(int seed) : rnd = math.Random(seed);
  final math.Random rnd;
  PlayerInput prev = PlayerInput.none;

  PlayerInput input(int side, MatchState s, int t) {
    final dir = facing(side);
    var left = false, right = false, jump = false, act = false;
    void duel(double gap, double want, double guardRate) {
      if (gap > want + 10) dir > 0 ? right = true : left = true;
      if (gap < want - 30 && rnd.nextDouble() < 0.5) dir > 0 ? left = true : right = true;
      act = gap <= want + 20 && rnd.nextDouble() < 0.08;
      jump = rnd.nextDouble() < guardRate;
    }

    switch (s.world) {
      case RallyWorld w:
        final p = w.players[side], b = w.ball;
        final mine = side == 0 ? b.x < Field.center + 40 : b.x > Field.center - 40;
        final target = mine ? b.x - dir * 12 : Field.center - dir * 240;
        left = target < p.x - 8;
        right = target > p.x + 8;
        final dx = b.x - p.x, dy = b.y - (p.y - 90);
        act = math.sqrt(dx * dx + dy * dy) < 85 && t % 7 == 0;
        jump = mine && (b.x - p.x).abs() < 40 && b.y < p.y - 170 && b.vy > 0;
      case FencingWorld w:
        duel((w.players[1].x - w.players[0].x).abs(), 190, 0.03);
      case BoxingWorld w:
        duel((w.players[1].x - w.players[0].x).abs(), 120, 0.3);
    }
    final out = PlayerInput(left: left, right: right, jump: jump, act: act, jumpPressed: jump && !prev.jump, actPressed: act && !prev.act);
    prev = out;
    return out;
  }
}

void main() {
  test('4タイトルともボット同士で決着がつき、状態を JSON で往復できる', () {
    for (final game in GameKind.values) {
      final e = MatchEngine(game, firstServer: 0, random: math.Random(1));
      final bots = [Bot(42), Bot(7)];
      var t = 0, hits = 0;
      while (e.state.phase != MatchPhase.over && t < 600 * 60) {
        e.step([bots[0].input(0, e.state, t), bots[1].input(1, e.state, t + 3)], 1 / 60);
        hits += e.state.events.where((ev) => const {'bump', 'toss', 'spike', 'drive', 'drop', 'clear', 'smash', 'touche', 'punch', 'counter'}.contains(ev.type)).length;
        // 途中の状態も、送って受け取ったあと同じ内容になる
        if (t % 97 == 0) {
          final json = jsonEncode(e.state.toJson());
          expect(jsonEncode(MatchState.fromJson((jsonDecode(json) as Map).cast<String, Object?>()).toJson()), json);
        }
        t++;
      }
      expect(e.state.phase, MatchPhase.over, reason: '$game が決着しない');
      expect(hits, greaterThan(0), reason: '$game で一度も打てていない');
      // ignore: avoid_print
      print('${game.name}: ${e.state.score} 勝者 ${e.state.winner} ${e.state.endReason} ${t ~/ 60}秒 打球 $hits');
    }
  });

  test('バレー: サーブが相手コートに落ちるとサーブ側の得点、サーブ権が交代する', () {
    final e = MatchEngine(GameKind.volley, firstServer: 0);
    const idle = [PlayerInput.none, PlayerInput.none];
    for (var i = 0; i < MatchEngine.introTime * 60 + 30; i++) {
      e.step(idle, 1 / 60);
    }
    expect(e.state.phase, MatchPhase.play);
    e.step(const [PlayerInput(actPressed: true), PlayerInput.none], 1 / 60);
    for (var i = 0; i < 240 && e.state.phase == MatchPhase.play; i++) {
      e.step(idle, 1 / 60);
    }
    expect(e.state.score, [1, 0]);
    expect(e.state.lastPoint?.reason, 'イン');
    expect(e.state.server, 1);
  });

  test('連打は1回ずつ数え、前の試合からの押下回数は押したことにしない', () {
    final p = PressTracker()..baseline(const KeyState(jc: 5, ac: 9));
    expect(p.input(const KeyState(jc: 5, ac: 9), connected: true).actPressed, isFalse);
    expect(p.input(const KeyState(jc: 5, ac: 10), connected: true).actPressed, isTrue);
    expect(p.input(const KeyState(jc: 5, ac: 10), connected: true).actPressed, isFalse);
    expect(p.input(const KeyState(l: true, jc: 6), connected: false).left, isFalse, reason: '切断中は何も押していない扱い');
  });

  test('通信のフレームは1バイトずつ届いても、まとめて届いても同じに組み立てられる', () {
    final msgs = <Msg>[
      {'t': 'join', 'code': 'ACDE', 'name': 'たろう'},
      {'t': 'keys', 'k': const KeyState(l: true, jc: 3).toJson()},
      {'t': 'state', 's': MatchEngine(GameKind.boxing).state.toJson()},
    ];
    final all = [for (final m in msgs) ...WireCodec.encode(m)];
    final d1 = WireDecoder();
    final got = <Msg>[for (final b in all) ...d1.add([b])!];
    expect(jsonEncode(got), jsonEncode(msgs));
    expect(jsonEncode(WireDecoder().add(all)), jsonEncode(msgs));
    expect(WireDecoder().add([0, 0, 0, 3, 0x7b, 0x7b, 0x7b]), isNull, reason: '壊れたデータ');
  });

  test('部屋コード', () {
    final r = math.Random(3);
    for (var i = 0; i < 50; i++) {
      expect(RoomCode.isValid(RoomCode.make(r.nextInt)), isTrue);
    }
    expect(RoomCode.normalize(' ac-de '), 'ACDE');
    expect(RoomCode.isValid('AB'), isFalse);
  });
}
