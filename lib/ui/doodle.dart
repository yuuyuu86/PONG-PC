import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 白黒落書き風デザインの色と、手描き風の線を作る道具。
class Palette {
  static const paper = Color(0xFFF6F3EA);
  static const paperShade = Color(0xFFEAE5D7);
  static const ink = Color(0xFF1B1B1B);
  static const pencil = Color(0xFF7C786F);
  static const faint = Color(0x331B1B1B);
}

const kFontFamily = 'Yomogi';

class Sketch {
  /// 少し揺れた直線。seed を固定すれば毎フレーム同じ形になるのでチラつかない。
  /// [connect] が true なら [into] の現在位置から線をつなげる(多角形を塗れるようにするため)。
  static Path line(Offset a, Offset b, {int seed = 1, double wobble = 1.4, Path? into, bool connect = false}) {
    final path = into ?? Path();
    final rnd = math.Random(seed);
    final len = (b - a).distance;
    final steps = math.max(2, (len / 28).round());
    final normal = len == 0 ? Offset.zero : Offset(-(b.dy - a.dy) / len, (b.dx - a.dx) / len);
    // 線の端も少しずらして、ペンで引いた感じを出す
    Offset jitter(double t) {
      final edge = (t == 0 || t == 1) ? 0.6 : 1.0;
      return a + (b - a) * t + normal * ((rnd.nextDouble() * 2 - 1) * wobble * edge);
    }

    final pts = [for (var i = 0; i <= steps; i++) jitter(i / steps)];
    if (connect) {
      path.lineTo(pts.first.dx, pts.first.dy);
    } else {
      path.moveTo(pts.first.dx, pts.first.dy);
    }
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  static Path polygon(List<Offset> pts, {int seed = 1, double wobble = 1.4}) {
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      line(pts[i], pts[(i + 1) % pts.length], seed: seed * 31 + i, wobble: wobble, into: path, connect: i > 0);
    }
    return path..close();
  }

  static Path rect(Rect r, {int seed = 1, double wobble = 1.4}) =>
      polygon([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft], seed: seed, wobble: wobble);

  /// 少しいびつな円。始点と終点をわずかに重ねて手描きらしくする。
  static Path circle(Offset c, double r, {int seed = 1, double wobble = 0.08}) {
    final rnd = math.Random(seed);
    final path = Path();
    const n = 14;
    final start = rnd.nextDouble() * math.pi * 2;
    final radii = [for (var i = 0; i <= n + 1; i++) r * (1 + (rnd.nextDouble() * 2 - 1) * wobble)];
    for (var i = 0; i <= n + 1; i++) {
      final a = start + i / n * math.pi * 2;
      final p = c + Offset(math.cos(a), math.sin(a)) * radii[i];
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        final pa = start + (i - 0.5) / n * math.pi * 2;
        final cp = c + Offset(math.cos(pa), math.sin(pa)) * (radii[i] + radii[i - 1]) / 2 / math.cos(math.pi / n);
        path.quadraticBezierTo(cp.dx, cp.dy, p.dx, p.dy);
      }
    }
    return path;
  }

  /// 二度書きした線(ペンで重ねた感じ)を描く。
  static void strokeTwice(Canvas canvas, Path Function(int seed) build, Paint paint, {int seed = 1}) {
    canvas.drawPath(build(seed), paint);
    canvas.drawPath(build(seed + 7), paint..strokeWidth = paint.strokeWidth * 0.55);
  }

  static Paint pen(double width, {Color color = Palette.ink}) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static Paint fill(Color color) => Paint()..color = color;

  /// 斜線ハッチング(鉛筆で塗った感じ)を rect の中に clip して描く。
  static void hatch(Canvas canvas, Path clip, Rect bounds, {double gap = 7, double width = 1, Color color = Palette.faint, int seed = 3}) {
    canvas.save();
    canvas.clipPath(clip);
    final p = pen(width, color: color);
    var i = 0;
    for (double d = -bounds.height; d < bounds.width; d += gap) {
      final a = Offset(bounds.left + d, bounds.bottom);
      final b = Offset(bounds.left + d + bounds.height, bounds.top);
      canvas.drawPath(line(a, b, seed: seed + i++, wobble: 0.8), p);
    }
    canvas.restore();
  }

  /// 点線(手描き風)。
  static void dashed(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 8, double gap = 7, int seed = 5}) {
    final len = (b - a).distance;
    if (len == 0) return;
    final dir = (b - a) / len;
    var i = 0;
    for (double t = 0; t < len; t += dash + gap) {
      final s = a + dir * t;
      final e = a + dir * math.min(len, t + dash);
      canvas.drawPath(line(s, e, seed: seed + i++, wobble: 0.6), paint);
    }
  }
}

/// 紙の背景。細かいシミと薄い罫線で紙の質感を出す。
class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, required this.child, this.vignette = true});
  final Widget child;

  /// 周りを少し暗くする（2台を並べる試合画面では付けない）
  final bool vignette;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PaperPainter(vignette: vignette),
      isComplex: true,
      willChange: false,
      child: child,
    );
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter({this.vignette = true});
  final bool vignette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Sketch.fill(Palette.paper));
    final rnd = math.Random(42);
    final speck = Paint()..color = const Color(0x14000000);
    final count = (size.width * size.height / 900).clamp(0, 2500).toInt();
    for (var i = 0; i < count; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(p, rnd.nextDouble() * 0.9 + 0.2, speck);
    }
    if (!vignette) return;
    final shade = Paint()
      ..shader = ui.Gradient.radial(
        size.center(Offset.zero),
        size.longestSide * 0.75,
        [const Color(0x00000000), const Color(0x16000000)],
      );
    canvas.drawRect(Offset.zero & size, shade);
  }

  @override
  bool shouldRepaint(covariant _PaperPainter old) => old.vignette != vignette;
}

/// 手描きの枠。ボタンやカードに使う。
class SketchBorderPainter extends CustomPainter {
  SketchBorderPainter({
    this.seed = 1,
    this.strokeWidth = 2.6,
    this.fillColor,
    this.shadow = true,
    this.dashed = false,
  });

  final int seed;
  final double strokeWidth;
  final Color? fillColor;
  final bool shadow;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset(strokeWidth, strokeWidth) & Size(size.width - strokeWidth * 2 - 3, size.height - strokeWidth * 2 - 3));
    if (shadow) {
      final shadowPath = Sketch.rect(r.shift(const Offset(4, 4)), seed: seed + 3, wobble: 1.6);
      canvas.drawPath(shadowPath, Sketch.fill(Palette.ink));
    }
    final body = Sketch.rect(r, seed: seed, wobble: 1.6);
    canvas.drawPath(body, Sketch.fill(fillColor ?? Palette.paper));
    if (dashed) {
      final p = Sketch.pen(strokeWidth);
      for (final (a, b) in [
        (r.topLeft, r.topRight),
        (r.topRight, r.bottomRight),
        (r.bottomRight, r.bottomLeft),
        (r.bottomLeft, r.topLeft),
      ]) {
        Sketch.dashed(canvas, a, b, p, seed: seed);
      }
    } else {
      Sketch.strokeTwice(canvas, (s) => Sketch.rect(r, seed: s, wobble: 1.6), Sketch.pen(strokeWidth), seed: seed);
    }
  }

  @override
  bool shouldRepaint(covariant SketchBorderPainter old) =>
      old.seed != seed || old.fillColor != fillColor || old.shadow != shadow || old.dashed != dashed || old.strokeWidth != strokeWidth;
}
