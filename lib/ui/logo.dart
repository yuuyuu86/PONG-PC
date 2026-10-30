import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'doodle.dart';

/// PONG! ロゴ。「！」の点はボール。
/// [flight] を 0→1 に進めると、ボールが [entry]（点からの相対位置）から飛んできて点に着地する。
class PongLogo extends StatelessWidget {
  const PongLogo({super.key, this.fontSize = 72, this.flight = 1, this.entry});

  final double fontSize;
  final double flight;
  final Offset? entry;

  @override
  Widget build(BuildContext context) {
    final k = fontSize / 72;
    return Semantics(
      header: true,
      label: 'PONG!',
      child: SizedBox(
        width: 360 * k,
        height: 120 * k,
        child: CustomPaint(painter: _LogoPainter(fontSize, flight, entry)),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.fontSize, this.flight, this.entry);
  final double fontSize;
  final double flight;
  final Offset? entry;

  /// 飛んでいる時間の割合。残りは着地後の小さな弾み。
  static const _air = 0.72;

  @override
  void paint(Canvas canvas, Size size) {
    final fs = fontSize;
    final k = fs / 72;
    final text = TextPainter(
      text: TextSpan(text: 'PONG', style: TextStyle(fontFamily: kFontFamily, fontSize: fs, color: Palette.ink, letterSpacing: 4 * k, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = fs * 0.13;
    final total = text.width + 6 * k + r * 2;
    final left = (size.width - total) / 2;
    final top = (size.height - text.height) / 2 + 6 * k;
    text.paint(canvas, Offset(left, top));

    // 「！」の棒（手描き）と、点の位置
    final baseline = top + fs * 0.84;
    final dot = Offset(left + text.width + 6 * k + r, baseline - r);
    final stemTop = Offset(dot.dx + 1.5 * k, top + fs * 0.14);
    final stemBottom = Offset(dot.dx, dot.dy - r - fs * 0.12);
    Sketch.strokeTwice(canvas, (s) => Sketch.line(stemTop, stemBottom, seed: s, wobble: 0.8 * k), Sketch.pen(fs * 0.08), seed: 4);
    // 静止時もボールを置いた点はくぼみ（影）で示す
    canvas.drawOval(Rect.fromCenter(center: dot + Offset(0, r * 0.95), width: r * 1.8, height: r * 0.45), Sketch.fill(Palette.faint));

    // 軌跡: 始点 → 頂点の上を通って点へ（二次ベジェ = 放物線）
    final from = dot + (entry ?? Offset(-330 * k, 46 * k));
    final lift = (from.dx - dot.dx).abs() * 0.45;
    final ctrl = Offset((from.dx + dot.dx) / 2, math.min(from.dy, dot.dy) - lift);
    Offset at(double t) => from * ((1 - t) * (1 - t)) + ctrl * (2 * (1 - t) * t) + dot * (t * t);

    final f = flight.clamp(0.0, 1.0);
    final ft = math.min(1.0, f / _air);
    // 飛んでいる間だけ、ボールのすぐ後ろに点線を残す（止まったロゴには出さない）
    if (ft < 1) {
      final pen = Sketch.pen(1.6 * k, color: Palette.pencil);
      final trailTo = ft;
      for (double t = math.max(0.0, ft - 0.3); t < trailTo; t += 0.012) {
        if (((t * 1000).round() ~/ 12).isEven) canvas.drawLine(at(t), at(math.min(trailTo, t + 0.007)), pen);
      }
    }

    var ball = at(ft);
    if (f > _air && f < 1) {
      // 着地後に2回小さく弾む
      final u = (f - _air) / (1 - _air);
      ball = ball - Offset(0, fs * 0.32 * (1 - u) * (math.sin(u * math.pi * 2)).abs());
    }
    canvas.drawCircle(ball, r, Sketch.fill(Colors.white));
    canvas.drawPath(Sketch.circle(ball, r, seed: 2), Sketch.pen(2.6 * k));
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.fontSize != fontSize || old.flight != flight || old.entry != entry;
}

/// アプリアイコン。手描きの「P」が主役で、右下に小さなボール。
class AppIconPainter extends CustomPainter {
  const AppIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset u(double x, double y) => Offset(x * s, y * s);
    // macOS のアイコン枠に合わせて少し内側に描く
    final card = Rect.fromLTRB(0.1 * s, 0.1 * s, 0.88 * s, 0.88 * s);
    final rr = RRect.fromRectAndRadius(card, Radius.circular(0.17 * s));
    canvas.drawRRect(rr.shift(u(0.018, 0.022)), Sketch.fill(Palette.ink));
    canvas.drawRRect(rr, Sketch.fill(Palette.paper));
    canvas.drawRRect(rr, Sketch.pen(0.022 * s));

    final pen = Sketch.pen(0.075 * s);
    // 縦棒
    Sketch.strokeTwice(canvas, (seed) => Sketch.line(u(0.35, 0.25), u(0.34, 0.76), seed: seed, wobble: 0.004 * s), pen, seed: 3);
    // ふくらみ: 棒の上から右へ回って棒の中ほどへ戻る
    Path bowl(int seed) {
      final rnd = math.Random(seed);
      double j() => (rnd.nextDouble() * 2 - 1) * 0.008;
      return Path()
        ..moveTo(0.35 * s, 0.25 * s)
        ..cubicTo((0.6 + j()) * s, (0.2 + j()) * s, (0.71 + j()) * s, (0.3 + j()) * s, (0.66 + j()) * s, (0.42 + j()) * s)
        ..cubicTo((0.62 + j()) * s, (0.53 + j()) * s, (0.47 + j()) * s, (0.54 + j()) * s, (0.33 + j()) * s, (0.52 + j()) * s);
    }

    Sketch.strokeTwice(canvas, bowl, pen, seed: 5);

    final ball = u(0.67, 0.7);
    final r = 0.06 * s;
    canvas.drawCircle(ball, r, Sketch.fill(Colors.white));
    canvas.drawPath(Sketch.circle(ball, r, seed: 2, wobble: 0.04), Sketch.pen(0.022 * s));
  }

  @override
  bool shouldRepaint(covariant AppIconPainter old) => false;
}

/// 起動時のスプラッシュ。ボールが画面の外から飛んできてロゴの「！」の点に着地する。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone, this.onLand});

  final VoidCallback onDone;
  final VoidCallback? onLand;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));
  var _landed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_landed && _c.value >= _LogoPainter._air) {
        _landed = true;
        widget.onLand?.call();
      }
    });
    _c.forward().then((_) => Future.delayed(const Duration(milliseconds: 700), _finish));
  }

  var _done = false;
  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: PaperBackground(
        child: LayoutBuilder(builder: (context, c) {
          final fs = math.min(96.0, c.maxWidth / 6);
          // 画面の左下の外から飛んでくる
          final entry = Offset(-(c.maxWidth / 2 + fs * 2.5), c.maxHeight * 0.25);
          return Center(
            child: AnimatedBuilder(
              animation: CurvedAnimation(parent: _c, curve: Curves.linear),
              builder: (context, _) => PongLogo(fontSize: fs, flight: _c.value, entry: entry),
            ),
          );
        }),
      ),
    );
  }
}

/// 毎フレーム時刻を知らせる（試合や紙飛行機の描き直し用）
class FrameClock extends StatefulWidget {
  const FrameClock({super.key, required this.builder, this.running = true});

  final Widget Function(BuildContext context, ValueNotifier<double> time) builder;
  final bool running;

  @override
  State<FrameClock> createState() => _FrameClockState();
}

class _FrameClockState extends State<FrameClock> with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final _ticker = createTicker((_) => _time.value = DateTime.now().millisecondsSinceEpoch / 1000);

  @override
  void initState() {
    super.initState();
    if (widget.running) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant FrameClock old) {
    super.didUpdateWidget(old);
    if (widget.running && !_ticker.isActive) _ticker.start();
    if (!widget.running && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _time);
}

/// キーの形（操作説明用）
class Keycap extends StatelessWidget {
  const Keycap(this.label, {super.key, this.size = 15});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SketchBorderPainter(seed: label.length + 40, strokeWidth: 1.8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 2, 13, 6),
        child: Text(label, style: TextStyle(fontSize: size, color: Palette.ink, height: 1.2)),
      ),
    );
  }
}
