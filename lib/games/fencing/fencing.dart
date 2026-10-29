import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;

import '../../ui/doodle.dart';
import '../core/common.dart';
import '../core/painting.dart';

/// PONG! フェンシング: ピスト上で間合いを測り、突き（J）とパリィ（Space）で読み合う。
/// 有効な突きで1点。同時の突きは相打ちで得点なし。後ろの端から出ると相手の得点。
enum FencerState { idle, windup, extend, recover, parry, parryRecover, parried }

class Fencer {
  Fencer(this.side) : x = FencingRules.enGarde[side];

  final int side;
  double x;
  double vx = 0;
  FencerState state = FencerState.idle;
  double timer = 0;
  double actBuf = 0;
  double guardBuf = 0;
  bool hit = false;

  Map<String, Object?> toJson() => {'s': side, 'x': r2(x), 'st': state.name, 'k': r2(timer)};

  static Fencer fromJson(Map<String, Object?> m) => Fencer((m['s'] as num).toInt())
    ..x = numD(m['x'])
    ..state = FencerState.values.byName(m['st'] as String)
    ..timer = numD(m['k']);
}

class FencingWorld extends GameWorld {
  List<Fencer> players = [Fencer(0), Fencer(1)];

  /// 先に当てた側（相打ちの判定待ち）
  int? pendingSide;
  double pendingTimer = 0;

  @override
  Map<String, Object?> toJson() => {'p': [for (final f in players) f.toJson()], 'ps': pendingSide};

  static FencingWorld fromJson(Map<String, Object?> m) => FencingWorld()
    ..players = [for (final f in m['p'] as List) Fencer.fromJson((f as Map).cast<String, Object?>())]
    ..pendingSide = (m['ps'] as num?)?.toInt();
}

class FencingRules extends SportRules {
  FencingRules._();
  static final instance = FencingRules._();

  static const pisteMin = 70.0;
  static const pisteMax = 890.0;
  static const enGarde = [Field.center - 150, Field.center + 150];
  static const bodyHalf = 14.0;
  static const minGap = 44.0;
  static const arm = 92.0; // 構えた剣先までの距離
  static const lungeExt = 48.0; // 突きで伸びる長さ

  static const tWindup = 0.07;
  static const tExtend = 0.16;
  static const tRecover = 0.3;
  static const tParry = 0.22;
  static const tParryRecover = 0.32;
  static const tParried = 0.55; // パリィされた側の硬直
  static const tDoubleWindow = 0.06; // 相打ちとみなす時間差

  @override
  int? get winScore => 5;
  @override
  ServeRule get serveRule => ServeRule.none;

  static double bladeTip(Fencer f) {
    var ext = 0.0;
    if (f.state == FencerState.extend) ext = lungeExt * math.min(1, 1 - f.timer / tExtend + 0.35);
    return f.x + facing(f.side) * (arm + ext);
  }

  @override
  GameWorld makeWorld() => FencingWorld();

  @override
  GameWorld worldFromJson(Map<String, Object?> json) => FencingWorld.fromJson(json);

  @override
  void serve(GameWorld world, int? server) {
    final w = world as FencingWorld;
    w
      ..players = [Fencer(0), Fencer(1)]
      ..pendingSide = null
      ..pendingTimer = 0;
  }

  @override
  StepResult? step(GameWorld world, List<PlayerInput> inputs, double dt, List<GameEvent> events, List<int> score) {
    final w = world as FencingWorld;
    for (var i = 0; i < 2; i++) {
      final f = w.players[i];
      final inp = inputs[i];
      final dir = facing(i);
      f.actBuf = inp.actPressed ? 0.1 : math.max(0, f.actBuf - dt);
      f.guardBuf = inp.jumpPressed ? 0.1 : math.max(0, f.guardBuf - dt);
      f.timer = math.max(0, f.timer - dt);

      if (f.state == FencerState.idle) {
        if (f.actBuf > 0) {
          f
            ..state = FencerState.windup
            ..timer = tWindup
            ..actBuf = 0
            ..hit = false;
          events.add(GameEvent('lunge', side: i));
        } else if (f.guardBuf > 0) {
          f
            ..state = FencerState.parry
            ..timer = tParry
            ..guardBuf = 0;
          events.add(GameEvent('guard', side: i));
        }
      } else if (f.timer <= 0) {
        switch (f.state) {
          case FencerState.windup:
            f
              ..state = FencerState.extend
              ..timer = tExtend;
          case FencerState.extend:
            f
              ..state = FencerState.recover
              ..timer = tRecover;
          case FencerState.parry:
            f
              ..state = FencerState.parryRecover
              ..timer = tParryRecover;
          default:
            f
              ..state = FencerState.idle
              ..timer = 0;
        }
      }

      // 足さばき: 構え中のみ前後に動ける。突きは前へ踏み込む
      final canMove = f.state == FencerState.idle || f.state == FencerState.parry || f.state == FencerState.parryRecover;
      final a = inp.axis;
      final target = canMove ? a * (a * dir > 0 ? 250 : 220) : 0.0;
      f.vx = approach(f.vx, target, 2400 * dt);
      if (f.state == FencerState.extend) f.vx = dir * 330;
      if (f.state == FencerState.parried) f.vx = -dir * 120;
      f.x += f.vx * dt;
    }

    // 2人はすれ違えない
    final a = w.players[0], b = w.players[1];
    if (b.x - a.x < minGap) {
      final mid = (a.x + b.x) / 2;
      a.x = mid - minGap / 2;
      b.x = mid + minGap / 2;
      a.vx = math.min(a.vx, 0);
      b.vx = math.max(b.vx, 0);
    }

    // 後ろの端から出たら相手の得点
    if (a.x < pisteMin) return PointResult(1, 'ピストの外');
    if (b.x > pisteMax) return PointResult(0, 'ピストの外');

    // 突きの判定
    for (var i = 0; i < 2; i++) {
      final f = w.players[i];
      final o = w.players[1 - i];
      if (f.state != FencerState.extend || f.hit) continue;
      final tip = bladeTip(f);
      if ((tip - o.x) * facing(i) < -bodyHalf) continue;
      f.hit = true;
      const y = Field.ground - 66;
      if (o.state == FencerState.parry) {
        f
          ..state = FencerState.parried
          ..timer = tParried;
        o
          ..state = FencerState.idle // パリィ成功側はすぐ反撃できる
          ..timer = 0;
        events.add(GameEvent('parry', side: 1 - i, x: tip, y: y));
        continue;
      }
      final p = w.pendingSide;
      if (p != null && p != i) {
        events.add(GameEvent('clash', x: tip, y: y));
        return PointResult(null, '相打ち');
      }
      w
        ..pendingSide = i
        ..pendingTimer = tDoubleWindow;
      events.add(GameEvent('touche', side: i, x: tip, y: y));
    }

    final p = w.pendingSide;
    if (p != null) {
      w.pendingTimer -= dt;
      if (w.pendingTimer <= 0) return PointResult(p, 'トゥシュ');
    }
    return null;
  }
}

class FencingPainter extends SportPainter {
  const FencingPainter();

  static Pose _pose(FencerState s) => switch (s) {
        FencerState.idle => Pose(lean: 0.05, armF: 1.35, armB: -2.5, legF: 0.5, legB: -0.55, kneeF: 0.45, kneeB: -0.2),
        FencerState.windup => Pose(lean: -0.02, armF: 1.1, armB: -2.6, legF: 0.45, legB: -0.5, kneeF: 0.4, kneeB: -0.2),
        FencerState.extend => Pose(lean: 0.28, armF: 1.57, armB: -1.4, legF: 1.05, legB: -0.85, kneeF: 0.15, kneeB: 0),
        FencerState.recover => Pose(lean: 0.15, armF: 1.45, armB: -2, legF: 0.8, legB: -0.7, kneeF: 0.3, kneeB: -0.1),
        FencerState.parry => Pose(lean: 0, armF: 2.0, armB: -2.5, legF: 0.45, legB: -0.5, kneeF: 0.4, kneeB: -0.2),
        FencerState.parryRecover => Pose(lean: 0.03, armF: 1.6, armB: -2.5, legF: 0.48, legB: -0.52, kneeF: 0.42, kneeB: -0.2),
        FencerState.parried => Pose(lean: -0.22, armF: 0.8, armB: -1.6, legF: 0.35, legB: -0.4, kneeF: 0.2, kneeB: -0.3),
      };

  @override
  void paintCourt(Canvas c) {
    const G = Field.ground;
    const lo = FencingRules.pisteMin, hi = FencingRules.pisteMax;
    ink(c, Sketch.line(const Offset(0, G + 14), const Offset(Field.width, G + 14), seed: 2), 2);
    hatchRect(c, const Rect.fromLTWH(0, G + 16, Field.width, Field.height - G - 16), gap: 14);
    // ピスト（細長い台）と、端の警告ゾーン
    const piste = Rect.fromLTRB(lo, G, hi, G + 14);
    c.drawRect(piste, Sketch.fill(Colors.white));
    hatchRect(c, const Rect.fromLTWH(lo, G, 70, 14), gap: 6, width: 1.2, color: Palette.ink, seed: 70);
    hatchRect(c, const Rect.fromLTWH(hi - 70, G, 70, 14), gap: 6, width: 1.2, color: Palette.ink, seed: 820);
    Sketch.strokeTwice(c, (s) => Sketch.rect(piste, seed: s, wobble: 1), Sketch.pen(3), seed: 4);
    // 中央線と構えの線
    ink(c, Sketch.line(const Offset(Field.center, G - 6), const Offset(Field.center, G + 20), seed: 7), 4);
    for (final x in FencingRules.enGarde) {
      ink(c, Sketch.line(Offset(x, G), Offset(x, G + 14), seed: x.toInt()), 2);
    }
    drawText(c, 'ここから出たら失点', const Offset(lo + 4, G + 34), size: 14, color: Palette.pencil, anchor: const Offset(0, 0.5));
    drawText(c, 'ここから出たら失点', const Offset(hi - 4, G + 34), size: 14, color: Palette.pencil, anchor: const Offset(1, 0.5));
  }

  @override
  void paint(Canvas c, GameWorld world, PaintInfo info) {
    final w = world as FencingWorld;
    for (var s = 0; s < 2; s++) {
      final f = w.players[s];
      final own = s == info.you;
      final dir = facing(s);
      final pose = _pose(f.state)
        ..armLenF = 28
        ..mask = true;
      final seed = s * 100 + (info.time * 6).floor() % 3;
      final j = Figure.draw(c, x: f.x, y: Field.ground, dir: dir, own: own, seed: seed, pose: pose, label: info.labels ? (own ? 'あなた' : 'あいて') : null);
      // 剣: 突きの最中は判定に使った剣先まで伸ばす
      final h = j.handF;
      final tip = FencingRules.bladeTip(f);
      final Offset end;
      switch (f.state) {
        case FencerState.extend:
          end = Offset(tip, h.dy - 2);
        case FencerState.parry:
          end = Offset(h.dx + dir * 34, h.dy - 58);
        case FencerState.parried:
          end = Offset(h.dx + dir * 50, h.dy + 40);
        default:
          final len = (tip - h.dx).abs();
          end = Offset(h.dx + dir * len * 0.97, h.dy - len * 0.22);
      }
      ink(c, Sketch.line(h, end, seed: seed + 9, wobble: 0.4), own ? 3 : 2);
      ink(c, Sketch.line(Offset(h.dx + dir * 4, h.dy - 7), Offset(h.dx + dir * 4, h.dy + 7), seed: seed + 8, wobble: 0.3), own ? 3.4 : 2.4);
      if (f.state == FencerState.parried) drawText(c, '？', Offset(f.x, Field.ground - 150), size: 26);
    }
    final p = w.pendingSide;
    if (p != null) drawText(c, '！', Offset(FencingRules.bladeTip(w.players[p]), Field.ground - 110), size: 34);
  }
}
