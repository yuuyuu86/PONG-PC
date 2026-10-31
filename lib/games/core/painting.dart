import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../avatar/avatar.dart';
import '../../avatar/avatar_painter.dart';
import '../../ui/doodle.dart';
import 'common.dart';
import 'match.dart';

/// 描画に渡す情報
class PaintInfo {
  const PaintInfo({required this.you, required this.time, required this.phase, this.server, this.avatars});

  /// 自分の側。-1 はカードの縮小図など（名札なし）
  final int you;
  final double time;
  final MatchPhase phase;
  final int? server;

  /// 選手の見た目（左・右）。あれば頭に髪・帽子・顔を描く
  final List<Avatar>? avatars;
  Avatar? avatarOf(int side) => avatars == null || side >= avatars!.length ? null : avatars![side];

  bool get labels => you >= 0;
}

/// 試合画面の上部に出す競技固有の情報（ボクシングの時計と体力など）
class HudExtra {
  const HudExtra(this.center, this.bars);
  final String center;
  final List<double> bars;

  @override
  bool operator ==(Object other) => other is HudExtra && other.center == center && other.bars[0] == bars[0] && other.bars[1] == bars[1];

  @override
  int get hashCode => Object.hash(center, bars[0], bars[1]);
}

/// 競技ごとの描画。座標は論理座標（960x540）で描く。
abstract class SportPainter {
  const SportPainter();
  void paintCourt(Canvas canvas);
  void paint(Canvas canvas, GameWorld world, PaintInfo info);
  HudExtra? hud(GameWorld world) => null;
}

/// 棒人間の姿勢。角度は真下=0、前方向が正（ラジアン）。
class Pose {
  Pose({
    this.lean = 0,
    this.armF = 0.5,
    this.armB = -0.3,
    this.armLenF = 30,
    this.armLenB = 30,
    this.legF = 0.25,
    this.legB = -0.25,
    this.kneeF = 0,
    this.kneeB = 0,
    this.headR = 13,
    this.scale = 1,
    this.mask = false,
  });

  double lean, armF, armB, armLenF, armLenB, legF, legB, kneeF, kneeB, headR, scale;
  bool mask;

  Pose copy() => Pose(
      lean: lean, armF: armF, armB: armB, armLenF: armLenF, armLenB: armLenB, legF: legF, legB: legB,
      kneeF: kneeF, kneeB: kneeB, headR: headR, scale: scale, mask: mask);
}

class Joints {
  const Joints(this.handF, this.handB, this.head);
  final Offset handF;
  final Offset handB;
  final Offset head;
}

Path polyline(List<Offset> pts, {int seed = 1, double wobble = 1.4}) {
  final p = Path();
  for (var i = 0; i < pts.length - 1; i++) {
    Sketch.line(pts[i], pts[i + 1], seed: seed * 31 + i, wobble: wobble, into: p, connect: i > 0);
  }
  return p;
}

void ink(Canvas c, Path p, double width, {Color color = Palette.ink}) => c.drawPath(p, Sketch.pen(width, color: color));

/// 斜線で塗る（スマホ版 Sketch.hatch）
void hatchRect(Canvas c, Rect r, {double gap = 7, double width = 1, Color color = Palette.faint, int seed = 3}) =>
    Sketch.hatch(c, Path()..addRect(r), r, gap: gap, width: width, color: color, seed: seed);

/// 交差した斜線（網目）
void crossHatch(Canvas c, Path clip, Rect r, {double gap = 6, double width = 1, Color color = Palette.ink, int seed = 3}) {
  Sketch.hatch(c, clip, r, gap: gap, width: width, color: color, seed: seed);
  c.save();
  c.translate(r.center.dx, r.center.dy);
  c.scale(-1, 1);
  c.translate(-r.center.dx, -r.center.dy);
  Sketch.hatch(c, clip, r, gap: gap, width: width, color: color, seed: seed + 5);
  c.restore();
}

final _textCache = <String, TextPainter>{};

/// Yomogi で文字を描く。anchor は (0.5, 0.5) で中央。
void drawText(Canvas c, String s, Offset at, {double size = 20, Color color = Palette.ink, Offset anchor = const Offset(0.5, 0.5)}) {
  final key = '$s|$size|${color.toARGB32()}';
  final tp = _textCache[key] ??= (TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontFamily: kFontFamily, fontSize: size, color: color, height: 1.1)),
    textDirection: TextDirection.ltr,
  )..layout());
  if (_textCache.length > 400) _textCache.clear();
  tp.paint(c, at - Offset(tp.width * anchor.dx, tp.height * anchor.dy));
}

abstract final class Figure {
  /// 棒人間を描く。自分の選手は太い線（色ではなく線の太さと名札で区別する）。
  static Joints draw(Canvas c, {required double x, required double y, required double dir, required bool own, required int seed, required Pose pose, String? label, Avatar? avatar}) {
    final p = pose;
    final w = own ? 5.2 : 2.6;
    final s = p.scale;
    final hip = Offset(x, y - 40 * s);
    final neck = Offset(hip.dx + math.sin(p.lean) * dir * 38 * s, hip.dy - math.cos(p.lean) * 38 * s);
    final head = Offset(neck.dx + math.sin(p.lean) * dir * (p.headR + 4) * s, neck.dy - math.cos(p.lean) * (p.headR + 4) * s);

    void leg(double a, double knee, int sd) {
      final k = Offset(hip.dx + math.sin(a) * dir * 21 * s, hip.dy + math.cos(a) * 21 * s);
      final f = Offset(k.dx + math.sin(a - knee) * dir * 21 * s, k.dy + math.cos(a - knee) * 21 * s);
      ink(c, polyline([hip, k, f], seed: seed + sd, wobble: 0.9), w);
    }

    leg(p.legB, p.kneeB, 10);
    leg(p.legF, p.kneeF, 20);
    ink(c, Sketch.line(hip, neck, seed: seed + 30, wobble: 0.9), w);

    final shoulder = Offset(hip.dx + (neck.dx - hip.dx) * 0.85, hip.dy + (neck.dy - hip.dy) * 0.85);
    Offset arm(double a, int sd, double len) {
      final h = Offset(shoulder.dx + math.sin(a) * dir * len * s, shoulder.dy + math.cos(a) * len * s);
      ink(c, Sketch.line(shoulder, h, seed: seed + sd, wobble: 0.9), w);
      return h;
    }

    final handB = arm(p.armB, 40, p.armLenB);
    final handF = arm(p.armF, 50, p.armLenF);

    final hr = p.headR * s;
    if (avatar != null && !p.mask) {
      // 自分で作った見た目（あたま・かお・かみ/ぼうし）を頭に描く
      AvatarPainter(avatar).paintHead(c, head, hr, facing: dir, lineWidth: w * 0.75);
      if (label != null) drawLabel(c, Offset(head.dx, head.dy - hr * 1.7 - 10), label, own);
      return Joints(handF, handB, head);
    }
    final headPath = Sketch.circle(head, hr, seed: seed + 60);
    c.drawPath(headPath, Sketch.fill(Palette.paper));
    if (p.mask) {
      // フェンシングのマスク: 網目
      crossHatch(c, headPath, Rect.fromCircle(center: head, radius: hr), gap: 5, seed: seed);
    } else {
      // 目で向きを示す
      c.drawCircle(Offset(head.dx + dir * 5 * s, head.dy - 2 * s), own ? 2.6 : 2, Sketch.fill(Palette.ink));
    }
    ink(c, headPath, w);
    if (label != null) drawLabel(c, Offset(head.dx, head.dy - hr - 10), label, own);
    return Joints(handF, handB, head);
  }

  /// 名札（スマホ版と同じ）: 自分は墨で塗った枠に紙色の文字、相手は点線の枠。
  static void drawLabel(Canvas c, Offset anchor, String text, bool own) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontFamily: kFontFamily, fontSize: own ? 18 : 15, color: own ? Palette.paper : Palette.ink, height: 1.1)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromLTWH(anchor.dx - tp.width / 2 - 8, anchor.dy - tp.height - 8, tp.width + 16, tp.height + 6);
    if (own) {
      c.drawPath(Sketch.rect(r, seed: 11, wobble: 0.8), Sketch.fill(Palette.ink));
      c.drawPath(
        Path()
          ..moveTo(anchor.dx - 6, r.bottom - 1)
          ..lineTo(anchor.dx + 6, r.bottom - 1)
          ..lineTo(anchor.dx, r.bottom + 7)
          ..close(),
        Sketch.fill(Palette.ink),
      );
    } else {
      c.drawPath(Sketch.rect(r, seed: 12, wobble: 0.8), Sketch.fill(Palette.paper));
      final pen = Sketch.pen(1.4);
      for (final (a, b) in [(r.topLeft, r.topRight), (r.topRight, r.bottomRight), (r.bottomRight, r.bottomLeft), (r.bottomLeft, r.topLeft)]) {
        Sketch.dashed(c, a, b, pen, dash: 4, gap: 3);
      }
    }
    tp.paint(c, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
  }

  /// ボールの地面の影（高いほど小さく薄く）と、影とボールを結ぶ細い点線（高さを読みやすく）
  static void shadow(Canvas c, Offset ball, double r) {
    final height = Field.ground - ball.dy;
    final k = math.max(0.25, 1 - height / 420);
    c.drawOval(Rect.fromCenter(center: Offset(ball.dx, Field.ground), width: r * 2.6 * k, height: 8 * k + 2), Sketch.fill(Palette.ink.withValues(alpha: 0.28 * k + 0.08)));
    if (height > r + 6 && ball.dy > 0) {
      Sketch.dashed(c, Offset(ball.dx, Field.ground), Offset(ball.dx, ball.dy + r), Sketch.pen(1, color: Palette.pencil), dash: 3, gap: 4);
    }
  }

  /// 画面の上へ出たボールの位置を示す矢印
  static void offscreenMarker(Canvas c, double x, double y) {
    if (y >= -10) return;
    ink(c, polyline([Offset(x - 8, 26), Offset(x, 16), Offset(x + 8, 26)], seed: 2), 3);
    ink(c, Sketch.line(Offset(x, 18), Offset(x, 40), seed: 1), 3);
    drawText(c, '↑${(-y).round()}', Offset(x, 54), size: 14);
  }

  /// 白いボールに太い輪郭と縫い目（スマホ版 paintBall）
  static void ball(Canvas c, Offset at, double r, double spin) {
    c.drawCircle(at, r + 2.5, Sketch.fill(Palette.paper));
    c.drawCircle(at, r, Sketch.fill(Colors.white));
    ink(c, Sketch.circle(at, r, seed: 2, wobble: 0.04), 3);
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(spin);
    final seam = Path()
      ..moveTo(-r * 0.7, -r * 0.35)
      ..quadraticBezierTo(0, r * 0.25, r * 0.7, -r * 0.35)
      ..moveTo(-r * 0.6, r * 0.45)
      ..quadraticBezierTo(0, r * 0.05, r * 0.6, r * 0.45);
    ink(c, seam, 1.5);
    c.restore();
  }
}

/// 打った瞬間などの短い衝撃線
class Burst {
  const Burst(this.x, this.y, this.born, {this.big = false});

  final double x;
  final double y;
  final double born;
  final bool big;
  static const life = 0.35;

  void draw(Canvas c, double now) {
    final k = (now - born) / life;
    if (k < 0 || k >= 1) return;
    final size = big ? 34.0 : 22.0;
    final pen = Sketch.pen(2.2, color: Palette.ink.withValues(alpha: 1 - k));
    for (var i = 0; i < 7; i++) {
      final a = i / 7 * math.pi * 2 + 0.3;
      final r1 = size * (0.5 + k * 0.8);
      final r2 = size * (1 + k * 1.1);
      c.drawPath(Sketch.line(Offset(x + math.cos(a) * r1, y + math.sin(a) * r1), Offset(x + math.cos(a) * r2, y + math.sin(a) * r2), seed: i, wobble: 0.6), pen);
    }
  }
}
