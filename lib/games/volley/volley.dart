import 'dart:math' as math;
import 'dart:ui';

import '../core/common.dart';
import '../core/painting.dart';
import '../rally/rally.dart';

/// PONG! バレー: 高いネット、高いジャンプ、ふわっとしたボール。
/// 自分のコートで3回まで触れる（レシーブ→トス→スパイク）。
abstract final class VolleyRules {
  static const netTop = Field.ground - 128;
  static const courtMin = 50.0;
  static const courtMax = 910.0;
  static const gravity = 900.0;
  static const autoServe = 6.0;

  static final instance = RallyRules(
    RallyConfig(
      netTop: netTop,
      netBounce: 0.45,
      ballR: 17,
      bodyHalf: 18,
      maxTouches: 3,
      courtMin: courtMin,
      courtMax: courtMax,
      serveX: const [110, 850],
      serveZone: const [(30, 200), (760, 930)],
      serveHold: const Offset(18, 118),
      autoServe: autoServe,
      runner: const RunnerParams(speed: 330, accel: 2600, airAccel: 1400, jumpV: 790, gravity: 2050, swingTime: 0.2, swingCooldown: 0.34),
      // ジャンプ中は打点が高くなる
      reach: (p) => p.onGround ? const Reach(8, 78, 72) : const Reach(14, 96, 76),
      serveShot: (dir) => Shot(dir * 360, -700, 'serve'),
      shot: _shot,
      moveBall: (ball, dt) {
        ball.vy += gravity * dt;
        final sp = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy);
        if (sp > 1100) {
          ball.vx *= 1100 / sp;
          ball.vy *= 1100 / sp;
        }
        ball.x += ball.vx * dt;
        ball.y += ball.vy * dt;
      },
    ),
    winScore: 5,
    serveRule: ServeRule.alternate,
  );

  static Shot _shot(ShotContext c) {
    final distToNet = math.max(10.0, (Field.center - c.ball.x).abs());
    // ジャンプ中、ネットより高い位置で打てばスパイク
    if (!c.player.onGround && c.ball.y < c.netTop - 6) {
      final power = 660 + clampD(c.rel, -30, 40) * 3;
      final t = distToNet / power;
      // ネット上端ぎりぎりを通る角度。前入力でさらに鋭く（ネットにかかる危険あり）
      final limit = (c.netTop - 30 - c.ball.y - 0.5 * gravity * t * t) / t;
      final down = clampD(limit * (c.toward > 0 ? 1.2 : 0.8), -160, 560);
      return Shot(c.dir * power, down, 'spike');
    }
    // 後ろ入力でトス（自分の真上に上げて次のスパイクにつなぐ）
    if (c.toward < 0) return Shot(c.dir * 60, -780, 'toss');
    // レシーブ: 打点が低いほど高く上がり、ボールが後ろにあるほど深く飛ぶ。前入力で奥を狙う
    final low = clampD((c.ball.y - (c.player.y - 78)) / 60, -1, 1);
    final vy = -clampD(720 + low * 90, 600, 860);
    final h = Field.ground - c.ball.r - c.ball.y;
    final flight = (-vy + math.sqrt(vy * vy + 2 * gravity * h)) / gravity;
    final depth = clampD(230 - c.rel * 2 + (c.toward > 0 ? 190 : 0), 90, 520);
    final vx = clampD((distToNet + depth) / flight, 90, 620);
    return Shot(c.dir * vx, vy, 'bump');
  }
}

class VolleyPainter extends SportPainter {
  const VolleyPainter();

  @override
  void paintCourt(Canvas canvas) =>
      RallyPaint.court(canvas, netTop: VolleyRules.netTop, courtMin: VolleyRules.courtMin, courtMax: VolleyRules.courtMax);

  @override
  void paint(Canvas canvas, GameWorld world, PaintInfo info) {
    final w = world as RallyWorld;
    RallyPaint.info(canvas, w, info, 3, VolleyRules.autoServe);
    final b = Offset(w.ball.x, w.ball.y);
    Figure.shadow(canvas, b, w.ball.r);
    Figure.offscreenMarker(canvas, b.dx, b.dy);
    for (var s = 0; s < 2; s++) {
      RallyPaint.player(canvas, w.players[s], own: s == info.you, racket: false, swingTime: 0.2, info: info);
    }
    Figure.ball(canvas, b, w.ball.r, w.ball.x / w.ball.r);
  }
}
