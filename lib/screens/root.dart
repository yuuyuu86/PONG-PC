import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../app/feedback.dart';
import '../app/services.dart';
import '../games/core/catalog.dart';
import '../games/core/painting.dart';
import '../net/wire.dart';
import '../ui/doodle.dart';
import '../ui/logo.dart';
import '../ui/widgets.dart';
import 'home.dart';
import 'info.dart';
import 'match.dart';
import 'profile.dart';
import 'records.dart';
import 'room.dart';
import 'setup.dart';

/// 画面の切り替えと、どの画面にも重ねるもの（接続の問題・招待状・紙飛行機）
class RootScreen extends StatefulWidget {
  const RootScreen({super.key, this.splash = true});

  /// 起動時にロゴのスプラッシュを流すか
  final bool splash;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  late var _splash = widget.splash;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// ウィンドウから離れたら押しっぱなしを解除する
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) Services.of(context).model.keyboard.releaseAll();
  }

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return ListenableBuilder(
      listenable: Listenable.merge([model, Services.of(context).settings]),
      builder: (context, _) {
        // const にしない: 部屋や試合の状態が変わるたびに画面を作り直す
        final settings = Services.of(context).settings;
        if (_splash) {
          return SplashScreen(onLand: () => Services.of(context).feedback.play(Sound.bounce), onDone: () => setState(() => _splash = false));
        }
        final screen = !settings.registered ? RegisterScreen() : switch (model.screen) {
          Screen.home => HomeScreen(),
          Screen.create => CreateScreen(),
          Screen.join => JoinScreen(),
          Screen.nearby => JoinScreen(nearby: true),
          Screen.room => RoomScreen(),
          Screen.match => MatchScreen(),
          Screen.result => ResultScreen(),
          Screen.howto => HowToScreen(),
          Screen.records => RecordsScreen(),
          Screen.settings => SettingsScreen(),
          Screen.profile => ProfileScreen(),
        };
        return Stack(
          children: [
            Positioned.fill(child: AnimatedSwitcher(duration: const Duration(milliseconds: 150), child: KeyedSubtree(key: ValueKey(model.screen), child: screen))),
            if (model.connection != null) Positioned.fill(child: ConnectionOverlay(problem: model.connection!)),
            if (model.invite != null) Positioned.fill(child: InviteLetter(invite: model.invite!)),
            Positioned.fill(child: IgnorePointer(child: PlaneLayer(flights: List.of(model.flights)))),
          ],
        );
      },
    );
  }
}

/// 操作キーの一覧
class ControlsList extends StatelessWidget {
  const ControlsList({super.key, required this.controls, this.size = 16});

  final List<GameControl> controls;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in controls)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Keycap(Services.of(context).settings.keys.describe(c.key), size: size - 2),
                const SizedBox(width: 10),
                Flexible(child: Text(c.label, style: TextStyle(fontSize: size))),
              ],
            ),
          ),
      ],
    );
  }
}

/// 縦に長い画面の共通の枠（中央寄せ・最大幅つき）
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1000});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
      primary: true,
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
      ),
    );
  }
}

/// 自分の接続が切れたとき
class ConnectionOverlay extends StatelessWidget {
  const ConnectionOverlay({super.key, required this.problem});

  final ConnectionProblem problem;

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return ColoredBox(
      color: Palette.paper.withValues(alpha: 0.8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DoodleBox(
            seed: 140,
            shadow: true,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(problem.title, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 12),
                if (!problem.isFinal) ...[const DoodleSpinner(size: 30), const SizedBox(height: 12)],
                Text(problem.body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, height: 1.45)),
                if (problem.since != null) ...[
                  const SizedBox(height: 8),
                  Countdown(since: problem.since!, builder: (left) => Text('あと $left 秒まで待ちます', style: const TextStyle(fontSize: 16, color: Palette.pencil))),
                ],
                const SizedBox(height: 18),
                DoodleButton(label: problem.isFinal ? 'タイトルへ戻る' : 'あきらめてタイトルへ', primary: problem.isFinal, seed: 141, onPressed: model.leaveRoom),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 待ち時間の残り秒数を1秒ごとに描き直す
class Countdown extends StatelessWidget {
  const Countdown({super.key, required this.since, required this.builder});

  final DateTime since;
  final Widget Function(int left) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(milliseconds: 500)),
      builder: (context, _) => builder(math.max(0, RoomInfo.graceSeconds - DateTime.now().difference(since).inSeconds)),
    );
  }
}

// ---------------------------------------------------------------------------
// 紙飛行機

/// ウィンドウ全体に重ねる紙飛行機のレイヤー（クリックは下へ通す）。軌跡はロゴと同じ鉛筆の点線。
class PlaneLayer extends StatelessWidget {
  const PlaneLayer({super.key, required this.flights});

  final List<Flight> flights;

  @override
  Widget build(BuildContext context) {
    if (flights.isEmpty) return const SizedBox.expand();
    return FrameClock(
      builder: (context, time) => CustomPaint(size: Size.infinite, painter: _PlanePainter(flights, time)),
    );
  }
}

class _PlanePainter extends CustomPainter {
  _PlanePainter(this.flights, this.time) : super(repaint: time);

  final List<Flight> flights;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    for (final f in flights) {
      final el = now.difference(f.start).inMicroseconds / 1e6;
      if (f.outbound) {
        _out(canvas, size, f, el);
      } else {
        _in(canvas, size, f, el);
      }
    }
  }

  /// 少し前までの位置を鉛筆の点線で結び、古い部分ほど薄くする
  void _trail(Canvas c, double t, double span, double fade, Offset Function(double) point) {
    const steps = 28;
    for (var i = 0; i < steps; i++) {
      final t0 = math.max(0.0, t - span * (steps - i) / steps);
      final t1 = math.max(0.0, t - span * (steps - i - 1) / steps);
      if (t1 <= t0 || i.isOdd) continue; // 1つおきに描いて点線にする
      c.drawLine(point(t0), point(t1), Sketch.pen(1.8, color: Palette.pencil.withValues(alpha: (i + 1) / steps * fade)));
    }
  }

  void _out(Canvas c, Size size, Flight f, double el) {
    if (el < PlaneMotion.pop) {
      final k = el / PlaneMotion.pop;
      drawPlane(c, f.from, -0.6 + math.sin(k * math.pi) * 0.5, scale: 0.3 + k * 0.7, flatten: 1 - k);
      return;
    }
    final path = PlaneMotion.outPath(f.from, size, f.yFrac);
    final raw = (el - PlaneMotion.pop) / PlaneMotion.outTravel;
    final t = math.min(1.0, raw);
    final fade = raw > 1 ? math.max(0.0, 1 - (raw - 1) * 2) : 1.0;
    Offset pos(double u) => PlaneMotion.bezier(path, PlaneMotion.outEase(u));
    _trail(c, t, 0.45, fade, pos);
    if (t >= 1) return;
    final p = pos(t), q = pos(math.max(0, t - 0.01));
    drawPlane(c, p, math.atan2(p.dy - q.dy, p.dx - q.dx), scale: 1 + t * 0.25);
  }

  void _in(Canvas c, Size size, Flight f, double el) {
    final raw = el / PlaneMotion.inTravel;
    final t = math.min(1.0, raw);
    final path = PlaneMotion.inPath(size, f.yFrac);
    Offset pos(double u) => PlaneMotion.bezier(path, PlaneMotion.inEase(u)) + Offset(0, math.sin(u * math.pi * 3) * 14 * (1 - u));
    final fade = raw > 1 ? math.max(0.0, 1 - (raw - 1) * 3) : 1.0;
    _trail(c, t, 0.4, fade, pos);
    final p = pos(t);
    if (t < 1) {
      final q = pos(math.max(0, t - 0.01));
      drawPlane(c, p, math.atan2(p.dy - q.dy, p.dx - q.dx), scale: 1.25 - t * 0.1);
    } else {
      // 着地: 機体を開いて招待状になる
      final k = math.min(1.0, (el - PlaneMotion.inTravel) / 0.32);
      drawPlane(c, p, 0, scale: 1.15 + k * 1.4, flatten: k, opacity: 1 - k);
    }
  }

  @override
  bool shouldRepaint(covariant _PlanePainter old) => true;
}

/// 上から見た紙飛行機（機首が +x）。片翼は影として斜線で塗る
void drawPlane(Canvas c, Offset at, double angle, {double scale = 1, double flatten = 0, double opacity = 1}) {
  if (opacity <= 0) return;
  c.saveLayer(null, Paint()..color = Colors.black.withValues(alpha: opacity));
  c.translate(at.dx, at.dy);
  c.rotate(angle);
  c.scale(scale, scale * (1 - flatten * 0.55));
  const nose = Offset(34, 0), top = Offset(-24, -19), bottom = Offset(-24, 17), tail = Offset(-13, 0);
  final under = Path()..addPolygon(const [nose, bottom, tail], true);
  c.drawPath(under, Sketch.fill(Palette.paperShade));
  Sketch.hatch(c, under, const Rect.fromLTWH(-26, 0, 62, 20), gap: 4, width: 0.9, color: Palette.pencil, seed: 4);
  c.drawPath(Path()..addPolygon(const [nose, top, tail], true), Sketch.fill(Colors.white));
  ink(c, polyline(const [nose, top, tail, bottom, nose], seed: 3, wobble: 0.5), 2.4);
  ink(c, Sketch.line(nose, tail, seed: 9, wobble: 0.4), 1.6);
  ink(c, Sketch.line(const Offset(32, -1), const Offset(-21, -9), seed: 11, wobble: 0.3), 1);
  c.restore();
}

/// 「2台を横に並べてね」の注意書き。左右の画面がつながってコートになるので、並べる向きをイラストで見せる。
/// [you] は 0 なら左（部屋を作った人）、1 なら右（参加する人）。
class SideBySideHint extends StatelessWidget {
  const SideBySideHint({super.key, required this.you});
  final int you;

  @override
  Widget build(BuildContext context) {
    final text = you == 0 ? '相手のPCを、このPCの右どなりに置いてください。' : 'このPCを、相手のPCの右どなりに置いてください。';
    return DoodleBox(
      seed: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [Icon(Icons.info_outline_rounded, color: Palette.ink), SizedBox(width: 8), DoodleHeading('2台を横にならべてね', size: 21)]),
          const SizedBox(height: 10),
          SizedBox(height: 150, child: CustomPaint(painter: _SideBySidePainter(you))),
          const SizedBox(height: 8),
          Text('$text 2台の画面がつながって、ひとつのコートになります。紙飛行機もとなりの画面へ飛んでいきます。', style: const TextStyle(fontSize: 16, height: 1.45)),
        ],
      ),
    );
  }
}

class _SideBySidePainter extends CustomPainter {
  _SideBySidePainter(this.you);
  final int you;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Sketch.pen(2.4);
    final thin = Sketch.pen(1.6);
    final w = math.min(170.0, size.width * 0.38);
    final h = w * 0.58;
    final gap = 10.0;
    final left = size.width / 2 - w - gap / 2;
    final top = 8.0;
    for (var i = 0; i < 2; i++) {
      final x = left + i * (w + gap);
      // 画面とキーボード
      final screen = Rect.fromLTWH(x, top, w, h);
      canvas.drawPath(Sketch.rect(screen, seed: 141 + i), Sketch.fill(i == you ? Palette.paperShade : Palette.paper));
      Sketch.strokeTwice(canvas, (s) => Sketch.rect(screen, seed: s), pen, seed: 141 + i);
      final base = Sketch.polygon([
        Offset(x - 8, top + h + 18),
        Offset(x + w + 8, top + h + 18),
        Offset(x + w, top + h + 4),
        Offset(x, top + h + 4),
      ], seed: 150 + i);
      canvas.drawPath(base, pen);
      // ラベル
      final tp = TextPainter(
        text: TextSpan(text: i == you ? 'このPC' : '相手のPC', style: const TextStyle(fontFamily: kFontFamily, fontSize: 15, color: Palette.ink)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + (w - tp.width) / 2, top + h + 22));
      // 画面の中: 床と棒人間
      final floor = top + h - 12;
      canvas.drawPath(Sketch.line(Offset(x + 8, floor), Offset(x + w - 8, floor), seed: 160 + i), thin);
      final px = i == 0 ? x + w * 0.3 : x + w * 0.7;
      canvas.drawCircle(Offset(px, floor - 30), 6, thin);
      canvas.drawPath(Sketch.line(Offset(px, floor - 24), Offset(px, floor - 10), seed: 170 + i), thin);
      canvas.drawPath(Sketch.line(Offset(px, floor - 10), Offset(px - 6, floor), seed: 172 + i), thin);
      canvas.drawPath(Sketch.line(Offset(px, floor - 10), Offset(px + 6, floor), seed: 174 + i), thin);
    }
    // 2台をまたいで飛ぶボール（点線の弧）
    final a = Offset(left + w * 0.35, top + h - 40);
    final b = Offset(left + w + gap + w * 0.65, top + h - 40);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo((a.dx + b.dx) / 2, top - 6, b.dx, b.dy);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, d + 6), thin);
      }
    }
    canvas.drawCircle(Offset((a.dx + b.dx) / 2, (a.dy + top - 6) / 2), 5, Sketch.fill(Palette.ink));
  }

  @override
  bool shouldRepaint(covariant _SideBySidePainter old) => old.you != you;
}
