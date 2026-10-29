import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'doodle.dart';

/// PONG! ロゴ。文字のまわりにボールの軌跡の点線とボールを描く（スマホ版と同じ）。
class PongLogo extends StatelessWidget {
  const PongLogo({super.key, this.fontSize = 72});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final k = fontSize / 72;
    return Semantics(
      header: true,
      label: 'PONG!',
      child: SizedBox(
        width: 360 * k,
        height: 120 * k,
        child: CustomPaint(
          painter: _LogoPainter(k),
          child: Center(
            child: Text('PONG!', style: TextStyle(fontSize: fontSize, color: Palette.ink, letterSpacing: 4 * k, height: 1)),
          ),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.k);
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Sketch.pen(1.6 * k, color: Palette.pencil);
    final path = Path()
      ..moveTo(c.dx - 150 * k, c.dy + 40 * k)
      ..quadraticBezierTo(c.dx - 60 * k, c.dy - 70 * k, c.dx + 30 * k, c.dy - 46 * k)
      ..quadraticBezierTo(c.dx + 110 * k, c.dy - 26 * k, c.dx + 140 * k, c.dy + 30 * k);
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 12 * k) {
        canvas.drawPath(metric.extractPath(d, math.min(metric.length, d + 6 * k)), p);
      }
    }
    final ball = Offset(c.dx + 146 * k, c.dy + 38 * k);
    canvas.drawCircle(ball, 9 * k, Sketch.fill(Colors.white));
    canvas.drawPath(Sketch.circle(ball, 9 * k, seed: 2), Sketch.pen(2.6 * k));
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.k != k;
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
