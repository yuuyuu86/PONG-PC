import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;

import '../../ui/doodle.dart';
import '../core/common.dart';
import '../core/painting.dart';

/// PONG! ボクシング: 移動・ガード（Space長押し）・パンチ（J）の読み合い。
/// 体力0でKO。60秒の制限時間が来たら有効打の多い方が勝ち。
/// 相手の振りかぶり中に当てるとカウンターで大ダメージ。
enum BoxerState { idle, windup, active, recover, stagger, blocked }

class Boxer {
  Boxer(this.side) : x = side == 0 ? 330 : 630;

  final int side;
  double x;
  double vx = 0;
  double hp = BoxingRules.maxHP;
  BoxerState state = BoxerState.idle;
  double timer = 0;
  bool guarding = false;
  double actBuf = 0;
  bool hit = false;

  /// 左右の拳を交互に出す
  int hand = 0;

  Map<String, Object?> toJson() => {'s': side, 'x': r2(x), 'hp': hp, 'st': state.name, 'k': r2(timer), 'g': guarding, 'h': hand};

  static Boxer fromJson(Map<String, Object?> m) => Boxer((m['s'] as num).toInt())
    ..x = numD(m['x'])
    ..hp = numD(m['hp'])
    ..state = BoxerState.values.byName(m['st'] as String)
    ..timer = numD(m['k'])
    ..guarding = m['g'] == true
    ..hand = (m['h'] as num).toInt();
}

class BoxingWorld extends GameWorld {
  List<Boxer> players = [Boxer(0), Boxer(1)];
  double clock = BoxingRules.timeLimit;

  @override
  Map<String, Object?> toJson() => {'p': [for (final b in players) b.toJson()], 'c': r2(clock)};

  static BoxingWorld fromJson(Map<String, Object?> m) => BoxingWorld()
    ..players = [for (final b in m['p'] as List) Boxer.fromJson((b as Map).cast<String, Object?>())]
    ..clock = numD(m['c']);
}

class BoxingRules extends SportRules {
  BoxingRules._();
  static final instance = BoxingRules._();

  static const ringMin = 90.0;
  static const ringMax = 870.0;
  static const timeLimit = 60.0;
  static const maxHP = 100.0;
  static const bodyHalf = 26.0;
  static const minGap = 74.0;
  static const reach = 112.0; // 体の中心から拳までの最大距離
  static const damage = 10.0;
  static const counterDamage = 16.0;
  static const chip = 2.0; // ガードの上から受けるダメージ（有効打には数えない）

  static const tWindup = 0.12;
  static const tActive = 0.08;
  static const tRecover = 0.22;
  static const tStagger = 0.32;
  static const tBlocked = 0.3;

  @override
  int? get winScore => null;
  @override
  ServeRule get serveRule => ServeRule.none;

  @override
  GameWorld makeWorld() => BoxingWorld();

  @override
  GameWorld worldFromJson(Map<String, Object?> json) => BoxingWorld.fromJson(json);

  @override
  void serve(GameWorld world, int? server) {
    // 1ラウンド制なので位置だけ整える
    for (final b in (world as BoxingWorld).players) {
      b
        ..x = b.side == 0 ? 330 : 630
        ..vx = 0
        ..state = BoxerState.idle
        ..timer = 0;
    }
  }

  @override
  StepResult? step(GameWorld world, List<PlayerInput> inputs, double dt, List<GameEvent> events, List<int> score) {
    final w = world as BoxingWorld;
    for (var i = 0; i < 2; i++) {
      final b = w.players[i];
      final inp = inputs[i];
      final dir = facing(i);
      b.actBuf = inp.actPressed ? 0.12 : math.max(0, b.actBuf - dt);
      b.timer = math.max(0, b.timer - dt);
      final busy = b.state != BoxerState.idle;
      b.guarding = inp.jump && b.state == BoxerState.idle;

      if (b.state == BoxerState.idle && b.actBuf > 0 && !b.guarding) {
        b
          ..state = BoxerState.windup
          ..timer = tWindup
          ..actBuf = 0
          ..hit = false
          ..hand = 1 - b.hand;
      } else if (busy && b.timer <= 0) {
        switch (b.state) {
          case BoxerState.windup:
            events.add(GameEvent('swing', side: i));
            b
              ..state = BoxerState.active
              ..timer = tActive;
          case BoxerState.active:
            b
              ..state = BoxerState.recover
              ..timer = tRecover;
          default:
            b
              ..state = BoxerState.idle
              ..timer = 0;
        }
      }

      final speed = b.guarding ? 120.0 : 240.0;
      b.vx = approach(b.vx, b.state == BoxerState.idle ? inp.axis * speed : 0, 2200 * dt);
      if (b.state == BoxerState.stagger) b.vx = -dir * 140;
      b.x = clampD(b.x + b.vx * dt, ringMin, ringMax);
      if (b.x == ringMin || b.x == ringMax) b.vx = 0;
    }

    final p0 = w.players[0], p1 = w.players[1];
    if (p1.x - p0.x < minGap) {
      final mid = (p0.x + p1.x) / 2;
      var a = mid - minGap / 2, c = mid + minGap / 2;
      if (a < ringMin) {
        a = ringMin;
        c = a + minGap;
      }
      if (c > ringMax) {
        c = ringMax;
        a = c - minGap;
      }
      p0.x = a;
      p1.x = c;
    }

    for (var i = 0; i < 2; i++) {
      final b = w.players[i];
      final o = w.players[1 - i];
      if (b.state != BoxerState.active || b.hit) continue;
      if ((o.x - b.x).abs() - bodyHalf > reach) continue;
      b.hit = true;
      final ax = o.x - facing(i) * bodyHalf;
      const ay = Field.ground - 82;
      if (o.guarding) {
        o
          ..hp = math.max(1, o.hp - chip)
          ..x = o.x + facing(i) * 10;
        b
          ..state = BoxerState.blocked
          ..timer = tBlocked;
        events.add(GameEvent('block', side: 1 - i, x: ax, y: ay));
        continue;
      }
      final counter = o.state == BoxerState.windup;
      o
        ..hp = math.max(0, o.hp - (counter ? counterDamage : damage))
        ..state = BoxerState.stagger
        ..timer = tStagger;
      events.add(GameEvent(counter ? 'counter' : 'punch', side: i, x: ax, y: ay));
      score[i]++; // 有効打
      if (o.hp <= 0) return EndResult(i, 'KO');
    }

    w.clock = math.max(0, w.clock - dt);
    if (w.clock <= 0) {
      if (score[0] != score[1]) return EndResult(score[0] > score[1] ? 0 : 1, '判定（有効打数）');
      if (p0.hp != p1.hp) return EndResult(p0.hp > p1.hp ? 0 : 1, '判定（体力）');
      return EndResult(-1, '引き分け');
    }
    return null;
  }
}

class BoxingPainter extends SportPainter {
  const BoxingPainter();

  static const postL = BoxingRules.ringMin - 46;
  static const postR = BoxingRules.ringMax + 46;

  @override
  void paintCourt(Canvas c) {
    const G = Field.ground;
    // リングの台とエプロン
    const apron = Rect.fromLTRB(postL - 20, G, postR + 20, G + 34);
    hatchRect(c, apron, gap: 10);
    Sketch.strokeTwice(c, (s) => Sketch.rect(apron, seed: s, wobble: 1.2), Sketch.pen(3), seed: 2);
    // ロープ（少したわむ）
    for (final (i, h) in const [(0, 52.0), (1, 96.0), (2, 140.0)]) {
      ink(c, Path()..moveTo(postL + 7, G - h)..quadraticBezierTo(Field.center, G - h + 10 + i, postR - 7, G - h), 2.2);
    }
    // コーナーポスト
    for (final x in const [postL, postR]) {
      final post = Rect.fromLTWH(x - 7, G - 160, 14, 160);
      c.drawRect(post, Sketch.fill(Colors.white));
      ink(c, Sketch.rect(post, seed: x.toInt(), wobble: 0.8), 3);
    }
  }

  @override
  void paint(Canvas c, GameWorld world, PaintInfo info) {
    final w = world as BoxingWorld;
    for (var s = 0; s < 2; s++) {
      final b = w.players[s];
      final own = s == info.you;
      final dir = facing(s);
      final seed = s * 100 + (info.time * 6).floor() % 3;
      final bob = b.state == BoxerState.idle && !b.guarding ? math.sin(info.time * 7 + s) * 2 : 0.0;
      final front = b.hand == 0; // 前の手・後ろの手のどちらでパンチしているか
      final pose = Pose(lean: 0.08, armF: 2.1, armB: 2.35, armLenF: 26, armLenB: 22, legF: 0.32, legB: -0.32, kneeF: 0.25, kneeB: -0.1, headR: 14, scale: 1.08);
      if (b.guarding) {
        pose
          ..armF = 2.75
          ..armB = 2.85
          ..armLenF = 24
          ..armLenB = 24
          ..lean = 0.02;
      }
      void extended() {
        if (front) {
          pose
            ..armF = 1.62
            ..armLenF = 66;
        } else {
          pose
            ..armB = 1.62
            ..armLenB = 66;
        }
        pose.lean = 0.2;
      }

      switch (b.state) {
        case BoxerState.windup:
          if (front) {
            pose
              ..armF = 1.9
              ..armLenF = 16;
          } else {
            pose
              ..armB = 1.9
              ..armLenB = 14;
          }
          pose.lean = -0.04;
        case BoxerState.active:
          extended();
        case BoxerState.recover when b.timer > 0.12:
          extended();
        case BoxerState.stagger:
          pose
            ..lean = -0.32
            ..armF = 1.2
            ..armB = 0.9;
        case BoxerState.blocked:
          pose.lean = -0.1;
        default:
      }
      final j = Figure.draw(c, x: b.x, y: Field.ground + bob, dir: dir, own: own, seed: seed, pose: pose, label: info.labels ? (own ? 'あなた' : 'あいて') : null, avatar: info.avatarOf(s));
      // グローブ（斜線で塗った丸）。自分は太い輪郭
      for (final h in [j.handB, j.handF]) {
        final g = Sketch.circle(h, 11, seed: seed + h.dx.toInt(), wobble: 0.05);
        c.drawPath(g, Sketch.fill(Palette.paper));
        Sketch.hatch(c, g, Rect.fromCircle(center: h, radius: 11), gap: 4, width: 1, color: Palette.ink, seed: 3);
        ink(c, g, own ? 4 : 2.4);
      }
      if (b.guarding) {
        // ガード中の目印: 顔の前の弧
        final start = dir > 0 ? -0.9 : math.pi - 0.9;
        ink(c, Path()..addArc(Rect.fromCircle(center: Offset(j.head.dx, j.head.dy + 8), radius: 34), start, 1.8), 2);
      }
      if (b.state == BoxerState.stagger) drawText(c, '＊ ＊', Offset(j.head.dx, j.head.dy - 30), size: 18);
    }
  }

  @override
  HudExtra? hud(GameWorld world) {
    final w = world as BoxingWorld;
    final t = w.clock.ceil();
    return HudExtra('${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}', [for (final b in w.players) b.hp / BoxingRules.maxHP]);
  }
}
