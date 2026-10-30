import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/doodle.dart';
import 'avatar.dart';

/// 棒人間を表示するウィジェット。[bust] なら顔まわりだけのアイコンにする。
class AvatarView extends StatelessWidget {
  const AvatarView({super.key, required this.avatar, this.size = 120, this.bust = false, this.mood = AvatarMood.normal, this.onDark = false, this.look});

  final Avatar avatar;
  final double size;

  /// 見ている向き（-1〜1）。指定すると顔がその向きに寄る
  final Offset? look;
  final bool bust;
  final AvatarMood mood;

  /// 黒い背景の上に置くとき (線を紙色にする)
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: bust ? size : size * 0.75,
        height: size,
        child: CustomPaint(painter: AvatarPainter(avatar, bust: bust, mood: mood, onDark: onDark, look: look)),
      ),
    );
  }
}

class AvatarPainter extends CustomPainter {
  AvatarPainter(this.avatar, {this.bust = false, this.mood = AvatarMood.normal, this.onDark = false, this.look});

  final Avatar avatar;
  final bool bust;
  final AvatarMood mood;
  final bool onDark;
  final Offset? look;

  // 1単位 = 全身の高さの1/10
  late double u;
  late double cx;
  late double y0;
  late Color ink;
  late Color paper;

  double y(double v) => y0 + v * u;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    cx = size.width / 2;
    if (bust) {
      // 頭と肩だけが収まるように拡大する
      u = size.height / 5.8;
      y0 = 0.1 * u;
    } else {
      u = math.min(size.height / 10.4, size.width / 6.4);
      y0 = (size.height - 10 * u) / 2;
    }
    ink = onDark ? Palette.paper : Palette.ink;
    paper = onDark ? Palette.ink : Palette.paper;

    final lose = mood == AvatarMood.lose;
    final pose = switch (mood) {
      AvatarMood.win => 1,
      AvatarMood.lose => -1,
      AvatarMood.normal => avatar[AvatarPart.pose],
    };
    final head = Offset(cx + (lose ? 0.25 * u : 0), y(lose ? 2.8 : 2.5));
    final r = 1.45 * u;

    // 顔アイコンでは手足を描かず、肩から上だけにする
    if (!bust) _legs(canvas, pose);
    _line(canvas, Offset(cx, head.dy + r * 0.8), Offset(cx, y(7)), 1);
    if (bust) _line(canvas, Offset(cx - 1.3 * u, y(5.4)), Offset(cx + 1.3 * u, y(5.4)), 2);
    if (!bust) _arms(canvas, pose);
    // おにぎり頭は上がとがっているので、帽子などは小さめに上へ、顔は下へずらす
    final onigiri = avatar[AvatarPart.head] == 3;
    final crown = onigiri ? head + Offset(0, -0.4 * r) : head;
    final crownR = onigiri ? r * 0.72 : r;
    final faceAt = onigiri ? head + Offset(0, 0.12 * r) : head;
    if (avatar[AvatarPart.top] == 5) _afro(canvas, head, r);
    _head(canvas, head, r);
    _face(canvas, faceAt + (look ?? Offset.zero) * (0.28 * r), onigiri ? r * 0.85 : r);
    _top(canvas, crown, crownR);
    if (mood == AvatarMood.win && !bust) _sparkles(canvas, head, r);
  }

  // ---- 線の道具 ----

  Paint _pen([double scale = 1]) => Sketch.pen(math.max(1.4, u * 0.3 * scale), color: ink);

  void _stroke(Canvas canvas, Path Function(int seed) build, {double scale = 1, int salt = 0}) =>
      canvas.drawPath(build(avatar.seed + salt), _pen(scale));

  void _line(Canvas canvas, Offset a, Offset b, int salt, {double scale = 1}) =>
      _stroke(canvas, (s) => Sketch.line(a, b, seed: s, wobble: u * 0.06), scale: scale, salt: salt);

  void _polyline(Canvas canvas, List<Offset> pts, int salt, {double scale = 1}) {
    for (var i = 0; i < pts.length - 1; i++) {
      _line(canvas, pts[i], pts[i + 1], salt + i, scale: scale);
    }
  }

  // ---- 体 ----

  void _legs(Canvas canvas, int pose) {
    final hip = Offset(cx, y(7));
    if (pose == 0) {
      // かまえ: ひざを曲げる
      _polyline(canvas, [hip, Offset(cx - 1.0 * u, y(8.3)), Offset(cx - 1.7 * u, y(9.8))], 10);
      _polyline(canvas, [hip, Offset(cx + 1.0 * u, y(8.3)), Offset(cx + 1.7 * u, y(9.8))], 20);
    } else {
      _line(canvas, hip, Offset(cx - 1.1 * u, y(9.8)), 10);
      _line(canvas, hip, Offset(cx + 1.1 * u, y(9.8)), 20);
    }
  }

  void _arms(Canvas canvas, int pose) {
    final shoulder = Offset(cx, y(4.9));
    switch (pose) {
      case 0: // かまえ: 右手でラケット
        _polyline(canvas, [shoulder, Offset(cx - 1.1 * u, y(5.9)), Offset(cx - 1.6 * u, y(6.9))], 30);
        final hand = Offset(cx + 1.9 * u, y(5.5));
        _polyline(canvas, [shoulder, Offset(cx + 1.1 * u, y(5.8)), hand], 40);
        _racket(canvas, hand, 0.5);
      case 1: // バンザイ
        _line(canvas, shoulder, Offset(cx - 1.9 * u, y(3.0)), 30);
        final hand = Offset(cx + 1.9 * u, y(3.0));
        _line(canvas, shoulder, hand, 40);
        _racket(canvas, hand, 0.25);
      case 2: // ピース
        _polyline(canvas, [shoulder, Offset(cx - 1.2 * u, y(6.0)), Offset(cx - 0.35 * u, y(6.9))], 30);
        final hand = Offset(cx + 1.6 * u, y(3.4));
        _polyline(canvas, [shoulder, Offset(cx + 1.3 * u, y(4.6)), hand], 40);
        _line(canvas, hand, hand + Offset(-0.25 * u, -0.8 * u), 50, scale: 0.8);
        _line(canvas, hand, hand + Offset(0.35 * u, -0.75 * u), 51, scale: 0.8);
      default: // がっくり
        _line(canvas, shoulder, Offset(cx - 0.8 * u, y(7.6)), 30);
        final hand = Offset(cx + 0.8 * u, y(7.6));
        _line(canvas, shoulder, hand, 40);
        _racket(canvas, hand, math.pi - 0.3);
    }
  }

  void _racket(Canvas canvas, Offset hand, double angle) {
    if (bust) return;
    // angle: 真上を0として時計回りに傾けた向き
    final dir = Offset(math.sin(angle), -math.cos(angle));
    final neck = hand + dir * 0.9 * u;
    _line(canvas, hand, neck, 60, scale: 0.8);
    canvas.save();
    canvas.translate(neck.dx + dir.dx * 0.75 * u, neck.dy + dir.dy * 0.75 * u);
    canvas.rotate(angle);
    final oval = Rect.fromCenter(center: Offset.zero, width: 1.1 * u, height: 1.5 * u);
    final path = Path()..addOval(oval);
    canvas.drawPath(path, Sketch.fill(paper));
    Sketch.hatch(canvas, path, oval.inflate(u), gap: u * 0.28, color: ink.withValues(alpha: 0.45), width: math.max(0.8, u * 0.06));
    canvas.drawPath(path, _pen(0.8));
    canvas.restore();
  }

  // ---- 頭 ----

  void _head(Canvas canvas, Offset c, double r) {
    final Path path;
    switch (avatar[AvatarPart.head]) {
      case 1: // たまご
        path = Path()..addOval(Rect.fromCenter(center: c, width: r * 1.7, height: r * 2.2));
      case 2: // しかく
        path = Sketch.rect(Rect.fromCenter(center: c, width: r * 1.95, height: r * 1.85), seed: avatar.seed, wobble: u * 0.05);
      case 3: // おにぎり
        path = Path()
          ..moveTo(c.dx, c.dy - r * 1.2)
          ..quadraticBezierTo(c.dx + r * 0.25, c.dy - r * 1.25, c.dx + r * 1.1, c.dy + r * 0.55)
          ..quadraticBezierTo(c.dx + r * 1.2, c.dy + r * 0.95, c.dx + r * 0.8, c.dy + r * 0.95)
          ..lineTo(c.dx - r * 0.8, c.dy + r * 0.95)
          ..quadraticBezierTo(c.dx - r * 1.2, c.dy + r * 0.95, c.dx - r * 1.1, c.dy + r * 0.55)
          ..quadraticBezierTo(c.dx - r * 0.25, c.dy - r * 1.25, c.dx, c.dy - r * 1.2)
          ..close();
      default:
        path = Sketch.circle(c, r, seed: avatar.seed, wobble: 0.04);
    }
    canvas.drawPath(path, Sketch.fill(paper));
    if (avatar[AvatarPart.head] == 3) {
      // のり
      canvas.drawRect(Rect.fromCenter(center: c + Offset(0, r * 0.8), width: r * 0.8, height: r * 0.3), Sketch.fill(ink));
    }
    canvas.drawPath(path, _pen());
  }

  void _face(Canvas canvas, Offset c, double r) {
    final eyeL = c + Offset(-0.4 * r, -0.08 * r);
    final eyeR = c + Offset(0.4 * r, -0.08 * r);
    final dot = math.max(1.6, 0.11 * r);
    final p = _pen(0.75);
    final dotFill = Sketch.fill(ink);

    void smile() => canvas.drawArc(Rect.fromCenter(center: c + Offset(0, 0.2 * r), width: 0.8 * r, height: 0.6 * r), 0.2 * math.pi, 0.6 * math.pi, false, p);

    if (mood == AvatarMood.lose) {
      canvas.drawLine(eyeL + Offset(-0.15 * r, 0), eyeL + Offset(0.15 * r, 0.06 * r), p);
      canvas.drawLine(eyeR + Offset(-0.15 * r, 0.06 * r), eyeR + Offset(0.15 * r, 0), p);
      canvas.drawArc(Rect.fromCenter(center: c + Offset(0, 0.62 * r), width: 0.6 * r, height: 0.4 * r), 1.15 * math.pi, 0.7 * math.pi, false, p);
      // 汗
      final drop = c + Offset(1.15 * r, -0.4 * r);
      canvas.drawPath(
        Path()
          ..moveTo(drop.dx, drop.dy - 0.3 * r)
          ..quadraticBezierTo(drop.dx + 0.2 * r, drop.dy, drop.dx, drop.dy + 0.12 * r)
          ..quadraticBezierTo(drop.dx - 0.2 * r, drop.dy, drop.dx, drop.dy - 0.3 * r),
        p,
      );
      return;
    }

    switch (avatar[AvatarPart.face]) {
      case 1: // キリッ
        canvas.drawLine(eyeL + Offset(-0.2 * r, -0.12 * r), eyeL + Offset(0.17 * r, 0.04 * r), _pen(0.9));
        canvas.drawLine(eyeR + Offset(-0.17 * r, 0.04 * r), eyeR + Offset(0.2 * r, -0.12 * r), _pen(0.9));
        canvas.drawLine(c + Offset(-0.25 * r, 0.45 * r), c + Offset(0.25 * r, 0.45 * r), p);
      case 2: // びっくり
        canvas.drawCircle(eyeL, 0.16 * r, p);
        canvas.drawCircle(eyeR, 0.16 * r, p);
        canvas.drawCircle(c + Offset(0, 0.48 * r), 0.16 * r, p);
      case 3: // ねむい
        canvas.drawArc(Rect.fromCenter(center: eyeL, width: 0.34 * r, height: 0.22 * r), 0, math.pi, false, p);
        canvas.drawArc(Rect.fromCenter(center: eyeR, width: 0.34 * r, height: 0.22 * r), 0, math.pi, false, p);
        canvas.drawCircle(c + Offset(0, 0.48 * r), 0.07 * r, p);
        if (!bust) _zzz(canvas, c + Offset(1.3 * r, -1.1 * r), r);
      case 4: // ウインク
        canvas.drawCircle(eyeL, dot, dotFill);
        canvas.drawPath(
          Path()
            ..moveTo(eyeR.dx - 0.17 * r, eyeR.dy + 0.04 * r)
            ..lineTo(eyeR.dx, eyeR.dy - 0.1 * r)
            ..lineTo(eyeR.dx + 0.17 * r, eyeR.dy + 0.04 * r),
          p,
        );
        smile();
      default: // にこにこ
        canvas.drawCircle(eyeL, dot, dotFill);
        canvas.drawCircle(eyeR, dot, dotFill);
        smile();
    }
  }

  void _zzz(Canvas canvas, Offset at, double r) {
    final tp = TextPainter(
      text: TextSpan(text: 'z z', style: TextStyle(fontFamily: kFontFamily, fontSize: r * 0.6, color: ink)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  void _afro(Canvas canvas, Offset c, double r) {
    final center = c + Offset(0, -0.2 * r);
    final cloud = Path();
    for (var i = 0; i < 11; i++) {
      final a = math.pi * (0.85 + i * 0.13);
      cloud.addOval(Rect.fromCircle(center: center + Offset(math.cos(a), math.sin(a)) * r * 1.05, radius: r * 0.5));
    }
    cloud.addOval(Rect.fromCircle(center: center, radius: r * 1.1));
    canvas.drawPath(cloud, Sketch.fill(ink));
  }

  void _top(Canvas canvas, Offset c, double r) {
    switch (avatar[AvatarPart.top]) {
      case 1: // ツンツン
        final pts = <Offset>[];
        for (var i = 0; i <= 8; i++) {
          final a = math.pi * (1.1 + 0.8 * i / 8);
          final rr = i.isOdd ? r * 1.5 : r * 0.98;
          pts.add(c + Offset(math.cos(a), math.sin(a)) * rr);
        }
        _polyline(canvas, pts, 70, scale: 0.85);
      case 2: // キャップ
        // 頭のてっぺんだけを覆い、目(中心のすこし上)にはかからないようにする
        const edge = 0.42; // つばの高さ (頭の中心から上へ r の何倍か)
        final rr = r * 1.06;
        final theta = math.asin(edge * r / rr);
        final dome = Path()
          ..addArc(Rect.fromCircle(center: c, radius: rr), math.pi + theta, math.pi - 2 * theta)
          ..close();
        canvas.drawPath(dome, Sketch.fill(ink));
        canvas.drawPath(dome, _pen(0.8));
        final brimY = -edge * r;
        _line(canvas, c + Offset(r * 0.55, brimY), c + Offset(r * 1.8, brimY + 0.1 * r), 80, scale: 1.4);
      case 3: // ハチマキ
        final band = Rect.fromCenter(center: c + Offset(0, -0.55 * r), width: r * 2.0, height: r * 0.32);
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 1.15)));
        canvas.drawRect(band, Sketch.fill(ink));
        canvas.restore();
        final knot = c + Offset(-r * 0.98, -0.55 * r);
        _line(canvas, knot, knot + Offset(-0.85 * r, 0.35 * r), 90, scale: 0.9);
        _line(canvas, knot, knot + Offset(-0.75 * r, -0.25 * r), 91, scale: 0.9);
      case 4: // リボン
        final k = c + Offset(math.cos(-0.3 * math.pi), math.sin(-0.3 * math.pi)) * r * 1.0;
        for (final s in [-1.0, 1.0]) {
          final wing = Path()
            ..moveTo(k.dx, k.dy)
            ..lineTo(k.dx + s * 0.75 * r, k.dy - 0.45 * r)
            ..lineTo(k.dx + s * 0.75 * r, k.dy + 0.4 * r)
            ..close();
          canvas.drawPath(wing, Sketch.fill(paper));
          canvas.drawPath(wing, _pen(0.7));
        }
        canvas.drawCircle(k, 0.18 * r, Sketch.fill(ink));
    }
  }

  void _sparkles(Canvas canvas, Offset c, double r) {
    final p = _pen(0.6);
    for (final (dx, dy) in [(-2.4, -0.6), (2.5, -1.1), (-2.0, 1.6)]) {
      final s = c + Offset(dx * u, dy * u);
      canvas.drawLine(s + Offset(-0.35 * u, 0), s + Offset(0.35 * u, 0), p);
      canvas.drawLine(s + Offset(0, -0.35 * u), s + Offset(0, 0.35 * u), p);
    }
  }

  @override
  bool shouldRepaint(covariant AvatarPainter old) =>
      old.avatar != avatar || old.bust != bust || old.mood != mood || old.onDark != onDark || old.look != look;
}
