import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;

import '../../ui/doodle.dart';
import '../core/common.dart';
import '../core/painting.dart';
import '../rally/rally.dart';

/// PONG! バドミントン: 低いネット、速い打ち出しと強い空気抵抗で急に失速するシャトル。
/// 1人1回で返す。入力方向でクリア / ドロップ、ジャンプ中の高い打点はスマッシュ。
abstract final class BadmintonRules {
  static const netTop = Field.ground - 82;
  static const courtMin = 60.0;
  static const courtMax = 900.0;
  static const gravity = 620.0;
  static const drag = 0.0029; // 速度の2乗に比例する空気抵抗
  static const autoServe = 6.0;

  /// 打球を角度（上向きが正）と初速で作る
  static Shot shotAt(double dir, double speed, double deg, String kind) {
    final a = deg * math.pi / 180;
    return Shot(dir * speed * math.cos(a), -speed * math.sin(a), kind);
  }

  static final instance = RallyRules(
    RallyConfig(
      netTop: netTop,
      netBounce: 0.15,
      ballR: 11,
      bodyHalf: 16,
      maxTouches: 1,
      courtMin: courtMin,
      courtMax: courtMax,
      serveX: const [150, 810],
      serveZone: const [(60, 240), (720, 900)],
      serveHold: const Offset(34, 52),
      autoServe: autoServe,
      runner: const RunnerParams(speed: 390, accel: 3400, airAccel: 1800, jumpV: 640, gravity: 2100, swingTime: 0.16, swingCooldown: 0.3),
      reach: (_) => const Reach(26, 96, 92), // ラケットの分だけ届く範囲が広い
      serveShot: (dir) => shotAt(dir, 780, 52, 'serve'),
      shot: (c) {
        final high = c.ball.y < c.player.y - 118;
        if (!c.player.onGround && high) return shotAt(c.dir, 1300, -14, 'smash');
        // 前入力: ネット際にふわっと落とすドロップ
        if (c.toward > 0) return shotAt(c.dir, 560 + clampD(-c.rel, -20, 40) * 2, 38, 'drop');
        // 後ろ入力: 高く遠くへ飛ばすクリア
        if (c.toward < 0) return shotAt(c.dir, 1200, 50, 'clear');
        // 入力なし: 速くて低いドライブ気味の返球
        return shotAt(c.dir, 900, high ? 22 : 40, 'drive');
      },
      moveBall: (ball, dt) {
        final sp = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy);
        ball.vx -= drag * sp * ball.vx * dt;
        ball.vy -= drag * sp * ball.vy * dt;
        ball.vy += gravity * dt;
        ball.x += ball.vx * dt;
        ball.y += ball.vy * dt;
      },
    ),
    winScore: 5,
    serveRule: ServeRule.winner,
  );
}

class BadmintonPainter extends SportPainter {
  const BadmintonPainter();

  @override
  void paintCourt(Canvas canvas) =>
      RallyPaint.court(canvas, netTop: BadmintonRules.netTop, courtMin: BadmintonRules.courtMin, courtMax: BadmintonRules.courtMax);

  @override
  void paint(Canvas canvas, GameWorld world, PaintInfo info) {
    final w = world as RallyWorld;
    RallyPaint.info(canvas, w, info, 1, BadmintonRules.autoServe);
    final b = Offset(w.ball.x, w.ball.y);
    Figure.shadow(canvas, b, 12);
    Figure.offscreenMarker(canvas, b.dx, b.dy);
    for (var s = 0; s < 2; s++) {
      RallyPaint.player(canvas, w.players[s], own: s == info.you, racket: true, swingTime: 0.16, info: info);
    }
    _shuttle(canvas, w.ball, w.serving);
  }

  /// シャトル: 黒いコルクが進行方向の先、白い羽根が後ろに広がる
  void _shuttle(Canvas c, Ball b, bool serving) {
    final still = b.vx == 0 && b.vy == 0;
    final ang = serving || still ? math.pi / 2 : math.atan2(b.vy, b.vx);
    c.save();
    c.translate(b.x, b.y);
    c.rotate(ang);
    const pts = [Offset(-2, -6), Offset(-24, -13), Offset(-24, 13), Offset(-2, 6)];
    c.drawPath(Path()..addPolygon(pts, true), Sketch.fill(Colors.white));
    ink(c, Sketch.polygon(pts, seed: 3, wobble: 0.5), 2.4);
    for (final (a, z) in const [(0.0, 0.0), (-3.0, -7.0), (3.0, 7.0)]) {
      ink(c, Sketch.line(Offset(-4, a), Offset(-24, z), seed: z.toInt() + 10, wobble: 0.3), 1);
    }
    final cork = Path()
      ..addArc(Rect.fromCircle(center: Offset.zero, radius: 7), -math.pi / 2, math.pi)
      ..lineTo(-2, 7)
      ..lineTo(-2, -7)
      ..close();
    c.drawPath(cork, Sketch.fill(Palette.ink));
    c.restore();
  }
}
