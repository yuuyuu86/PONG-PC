import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/doodle.dart';
import '../core/common.dart';
import '../core/match.dart';
import '../core/painting.dart';

/// ネットを挟んでボール（シャトル）を打ち合う競技の状態
class RallyWorld extends GameWorld {
  RallyWorld(this.players, this.ball);

  final List<Runner> players;
  Ball ball;
  int server = 0;
  bool serving = true;
  double serveClock = 0;
  int? lastHitter;
  List<int> touches = [0, 0];
  String? lastShot;
  double lastHitAt = 0;
  double clock = 0;
  bool netTouched = false;

  @override
  Map<String, Object?> toJson() => {
        'p': [for (final p in players) p.toJson()],
        'b': ball.toJson(),
        'sv': server,
        'sg': serving,
        'sc': r2(serveClock),
        'lh': lastHitter,
        't': touches,
        'ls': lastShot,
      };

  static RallyWorld fromJson(Map<String, Object?> m) => RallyWorld(
        [for (final p in m['p'] as List) Runner.fromJson((p as Map).cast<String, Object?>())],
        Ball.fromJson((m['b'] as Map).cast<String, Object?>()),
      )
        ..server = (m['sv'] as num).toInt()
        ..serving = m['sg'] == true
        ..serveClock = numD(m['sc'])
        ..lastHitter = (m['lh'] as num?)?.toInt()
        ..touches = [for (final v in m['t'] as List) (v as num).toInt()]
        ..lastShot = m['ls'] as String?;
}

class ShotContext {
  const ShotContext({required this.player, required this.ball, required this.dir, required this.toward, required this.rel, required this.netTop});

  final Runner player;
  final Ball ball;
  final double dir;

  /// +1: ネット側へ入力, -1: 後ろへ入力
  final double toward;

  /// 選手から見たボールの前後位置（前が正）
  final double rel;
  final double netTop;
}

class Shot {
  const Shot(this.vx, this.vy, this.kind);
  final double vx;
  final double vy;
  final String kind;
}

class Reach {
  const Reach(this.dx, this.dy, this.r);
  final double dx;
  final double dy;
  final double r;
}

/// ネット競技の設定。打ち方・弾道・選手の動きを競技ごとに決める。
class RallyConfig {
  const RallyConfig({
    required this.netTop,
    required this.netBounce,
    required this.ballR,
    required this.bodyHalf,
    required this.maxTouches,
    required this.courtMin,
    required this.courtMax,
    required this.serveX,
    required this.serveZone,
    required this.serveHold,
    required this.autoServe,
    required this.runner,
    required this.reach,
    required this.serveShot,
    required this.shot,
    required this.moveBall,
  });

  final double netTop;
  final double netBounce;
  final double ballR;
  final double bodyHalf;
  final int maxTouches;
  final double courtMin;
  final double courtMax;
  final List<double> serveX;
  final List<(double, double)> serveZone;
  final Offset serveHold;
  final double autoServe;
  final RunnerParams runner;
  final Reach Function(Runner) reach;
  final Shot Function(double dir) serveShot;
  final Shot Function(ShotContext) shot;
  final void Function(Ball, double dt) moveBall;
}

/// サーブ、ネット衝突、着地・アウト判定、タッチ数制限をまとめたネット競技の共通ルール
class RallyRules extends SportRules {
  RallyRules(this.cfg, {required this.winScore, required this.serveRule}) : net = Net(top: cfg.netTop, bounce: cfg.netBounce);

  final RallyConfig cfg;
  final Net net;
  @override
  final int? winScore;
  @override
  final ServeRule serveRule;

  static const homeX = [Field.center - 240, Field.center + 240];

  (double, double) _bounds(int side) => side == 0
      ? (20, Field.center - net.w / 2 - cfg.bodyHalf)
      : (Field.center + net.w / 2 + cfg.bodyHalf, Field.width - 20);

  @override
  RallyWorld makeWorld() => RallyWorld([Runner(0, homeX[0]), Runner(1, homeX[1])], Ball(cfg.ballR));

  @override
  GameWorld worldFromJson(Map<String, Object?> json) => RallyWorld.fromJson(json);

  void _placeBallOnServer(RallyWorld w) {
    final p = w.players[w.server];
    w.ball
      ..x = p.x + facing(w.server) * cfg.serveHold.dx
      ..y = p.y - cfg.serveHold.dy
      ..vx = 0
      ..vy = 0;
  }

  void _launch(RallyWorld w, int side, Shot shot, List<GameEvent> events) {
    w.ball
      ..vx = shot.vx
      ..vy = shot.vy;
    w.lastHitter = side;
    w.touches[1 - side] = 0;
    w.touches[side]++;
    w.lastShot = shot.kind;
    w.lastHitAt = w.clock;
    events.add(GameEvent(shot.kind, side: side, x: w.ball.x, y: w.ball.y));
  }

  @override
  void serve(GameWorld world, int? server) {
    final w = world as RallyWorld;
    final s = server ?? 0;
    w
      ..server = s
      ..serving = true
      ..serveClock = 0
      ..lastHitter = null
      ..touches = [0, 0]
      ..lastShot = null;
    for (var i = 0; i < 2; i++) {
      w.players[i] = Runner(i, i == s ? cfg.serveX[i] : homeX[i])..cd = 0.2;
    }
    _placeBallOnServer(w);
  }

  @override
  StepResult? step(GameWorld world, List<PlayerInput> inputs, double dt, List<GameEvent> events, List<int> score) {
    final w = world as RallyWorld;
    w.clock += dt;
    for (var i = 0; i < 2; i++) {
      final (lo, hi) = _bounds(i);
      if (w.serving && i == w.server) {
        // サーブ側は後方エリアに留まり、ジャンプしない
        final params = cfg.runner.within(cfg.serveZone[i].$1, cfg.serveZone[i].$2);
        final swung = w.players[i].step(inputs[i].copyWith(jump: false, jumpPressed: false), dt, params);
        _placeBallOnServer(w);
        w.serveClock += dt;
        if (swung || w.serveClock > cfg.autoServe) {
          w.serving = false;
          _launch(w, i, cfg.serveShot(facing(i)), events);
          w.players[i].swingHit = true;
        }
        continue;
      }
      w.players[i].step(inputs[i], dt, cfg.runner.within(lo, hi));
    }
    if (w.serving) return null;

    // 返球判定: 振っている間に打点の近くへ来たら打ち返す
    for (var i = 0; i < 2; i++) {
      final p = w.players[i];
      if (p.swing <= 0 || p.swingHit) continue;
      // 1回で返す競技では続けて触れない。3回まで触れる競技でも打った直後の同じボールは打てない
      if (w.lastHitter == i && (cfg.maxTouches == 1 || w.clock - w.lastHitAt < 0.3)) continue;
      final dir = facing(i);
      final reach = cfg.reach(p);
      final dx = w.ball.x - (p.x + dir * reach.dx);
      final dy = w.ball.y - (p.y - reach.dy);
      if (dx * dx + dy * dy > reach.r * reach.r) continue;
      final ctx = ShotContext(player: p, ball: w.ball, dir: dir, toward: inputs[i].axis * dir, rel: (w.ball.x - p.x) * dir, netTop: cfg.netTop);
      p.swingHit = true;
      _launch(w, i, cfg.shot(ctx), events);
      if (w.touches[i] > cfg.maxTouches) return PointResult(1 - i, 'タッチ数オーバー');
    }

    cfg.moveBall(w.ball, dt);
    if (collideNet(w.ball, net)) {
      if (!w.netTouched) events.add(const GameEvent('net'));
      w.netTouched = true;
    } else {
      w.netTouched = false;
    }

    final b = w.ball;
    // 画面の左右外へ出たらアウト
    if (b.x < -b.r * 2 || b.x > Field.width + b.r * 2) {
      final faulter = w.lastHitter ?? (b.x < 0 ? 0 : 1);
      return PointResult(1 - faulter, 'アウト', landX: b.x < 0 ? 0 : Field.width);
    }
    if (b.y + b.r >= Field.ground) {
      b.y = Field.ground - b.r;
      events.add(GameEvent('land', x: b.x));
      if (b.x < cfg.courtMin || b.x > cfg.courtMax) {
        final faulter = w.lastHitter ?? (b.x < Field.center ? 0 : 1);
        return PointResult(1 - faulter, 'アウト', landX: b.x);
      }
      final landed = b.x < Field.center ? 0 : 1;
      return PointResult(1 - landed, 'イン', landX: b.x);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// ネット競技の共通描画: コート、ネット、選手、サーブ案内

abstract final class RallyPaint {
  static void court(Canvas c, {required double netTop, required double courtMin, required double courtMax}) {
    const W = Field.width, H = Field.height, G = Field.ground;
    // 床と、コートの外（アウト）を薄い斜線で示す
    Sketch.strokeTwice(c, (s) => Sketch.line(const Offset(0, G), const Offset(W, G), seed: s), Sketch.pen(3), seed: 11);
    hatchRect(c, const Rect.fromLTWH(0, G + 4, W, H - G - 4), gap: 14);
    hatchRect(c, Rect.fromLTWH(0, G - 26, courtMin, 24), gap: 8, color: Palette.pencil.withValues(alpha: 0.6), seed: 5);
    hatchRect(c, Rect.fromLTWH(courtMax, G - 26, W - courtMax, 24), gap: 8, color: Palette.pencil.withValues(alpha: 0.6), seed: 6);
    ink(c, Sketch.line(Offset(courtMin, G - 2), Offset(courtMin, G + 18), seed: 12), 4);
    ink(c, Sketch.line(Offset(courtMax, G - 2), Offset(courtMax, G + 18), seed: 13), 4);
    drawText(c, 'OUT', Offset(courtMin / 2, G + 30), size: 15, color: Palette.pencil);
    drawText(c, 'OUT', Offset((courtMax + W) / 2, G + 30), size: 15, color: Palette.pencil);

    // ネット: 網目・両端の線・白い上端
    const nw = 8.0;
    const l = Field.center - nw / 2;
    final mesh = Rect.fromLTWH(l - 6, netTop, nw + 12, G - netTop);
    c.drawRect(Rect.fromLTWH(l, netTop, nw, G - netTop), Sketch.fill(Palette.paper));
    crossHatch(c, Path()..addRect(mesh), mesh, gap: 6, color: Palette.ink.withValues(alpha: 0.85), seed: 21);
    ink(c, Sketch.line(Offset(l - 6, netTop), const Offset(l - 6, G), seed: 23), 2);
    ink(c, Sketch.line(Offset(l + nw + 6, netTop), const Offset(l + nw + 6, G), seed: 24), 2);
    final band = Rect.fromLTWH(l - 9, netTop - 6, nw + 18, 10);
    c.drawRect(band, Sketch.fill(Colors.white));
    ink(c, Sketch.rect(band, seed: 25, wobble: 0.8), 2.6);
    ink(c, Sketch.line(Offset(Field.center, netTop - 6), Offset(Field.center, netTop - 22), seed: 26), 3);
  }

  /// 走る・跳ぶ・振るの姿勢
  static void player(Canvas c, Runner p, {required bool own, required bool racket, required double swingTime, required PaintInfo info}) {
    final dir = facing(p.side);
    final pose = Pose(legF: 0.18, legB: -0.18, kneeF: -0.15, kneeB: 0.1, lean: 0.08);
    if (!p.onGround) {
      pose
        ..legF = 0.55
        ..kneeF = 1.1
        ..legB = -0.1
        ..kneeB = 0.9
        ..lean = 0;
    } else if (p.vx.abs() > 30) {
      final sw = math.sin(p.x * 0.09) * 0.65;
      pose
        ..legF = sw
        ..legB = -sw
        ..kneeF = -0.2
        ..kneeB = -0.2
        ..lean = p.vx * dir > 0 ? 0.18 : -0.05;
    }
    final double? k = p.swing > 0 ? 1 - p.swing / swingTime : null;
    if (!racket) {
      // 構えは両腕を前に、振ると下から上へ（ジャンプ中は上から振り下ろす）
      if (k == null) {
        pose
          ..armF = 0.9
          ..armB = 0.7;
      } else if (p.onGround) {
        pose
          ..armF = 0.7 + k * 1.9
          ..armB = 0.5 + k * 1.7;
      } else {
        pose
          ..armF = 3.0 - k * 1.6
          ..armB = 2.6 - k * 1.2;
      }
    } else {
      // ラケットは前の手。振ると後ろから前上へ
      pose.armF = k == null ? 1.6 : (p.onGround ? 0.4 + k * 2.4 : 3.4 - k * 1.9);
      pose.armB = k == null ? -0.6 : -0.8;
    }
    final seed = p.side * 100 + (info.time * 6).floor() % 3; // 少しだけ線がゆらぐ
    final j = Figure.draw(c, x: p.x, y: p.y, dir: dir, own: own, seed: seed, pose: pose, label: info.labels ? (own ? 'あなた' : 'あいて') : null, avatar: info.avatarOf(p.side));
    if (racket) {
      final h = j.handF;
      final ax = math.sin(pose.armF) * dir;
      final ay = math.cos(pose.armF);
      final e = Offset(h.dx + ax * 26, h.dy + ay * 26);
      ink(c, Sketch.line(h, e, seed: seed + 3, wobble: 0.5), own ? 3.4 : 2.2);
      c.save();
      c.translate(e.dx + ax * 14, e.dy + ay * 14);
      c.rotate(math.atan2(ay, ax));
      const face = Rect.fromLTWH(-15, -10, 30, 20);
      final facePath = Path()..addOval(face);
      c.drawPath(facePath, Sketch.fill(Palette.paper));
      Sketch.hatch(c, facePath, face, gap: 4, width: 0.8, color: Palette.ink.withValues(alpha: 0.5), seed: 50);
      ink(c, facePath, own ? 3.4 : 2.2);
      c.restore();
    }
  }

  /// サーブ待ちの案内とタッチ数
  static void info(Canvas c, RallyWorld w, PaintInfo info, int maxTouches, double autoServe) {
    if (w.serving && info.phase == MatchPhase.play && info.labels) {
      final p = w.players[w.server];
      final mine = w.server == info.you;
      final left = math.max(0, (autoServe - w.serveClock).ceil());
      drawText(c, mine ? 'J でサーブ（$left秒で自動）' : 'あいてのサーブ', Offset(p.x, Field.ground + 50), size: mine ? 20 : 16, color: mine ? Palette.ink : Palette.pencil);
    }
    if (maxTouches > 1 && !w.serving) {
      for (var s = 0; s < 2; s++) {
        if (w.touches[s] == 0) continue;
        final cx = s == 0 ? Field.center - 140 : Field.center + 140;
        drawText(c, 'タッチ ${w.touches[s]}/$maxTouches', Offset(cx, 40), size: 17, color: w.touches[s] >= maxTouches ? Palette.ink : Palette.pencil);
      }
    }
  }
}
