import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../app/services.dart';
import '../avatar/avatar.dart';
import '../avatar/avatar_editor.dart';
import '../avatar/avatar_painter.dart';
import '../games/core/catalog.dart';
import '../games/core/common.dart';
import '../games/core/match.dart';
import '../games/core/painting.dart';
import '../ui/doodle.dart';
import '../ui/logo.dart';
import '../ui/widgets.dart';
import 'root.dart';

/// 試合画面: 上にスコア、真ん中にコート全体（両方のPCで同じ向き）、下に操作の案内。
class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    final game = model.room?.game ?? GameKind.volley;
    return Scaffold(
      backgroundColor: Palette.paper,
      body: PaperBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: ListenableBuilder(
              listenable: model.feed,
              builder: (context, _) => Column(
                children: [
                  _MatchHud(game: game),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: CustomPaint(
                          painter: SketchBorderPainter(seed: 110, strokeWidth: 3),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 6, 10, 10),
                            child: Stack(
                              children: [
                                Positioned.fill(child: CourtView(feed: model.feed, you: model.you)),
                                Positioned.fill(child: _Overlays(game: game)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ControlStrip(game: game),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// コート。60fps でホストから届いた最新の状態を描く。
class CourtView extends StatelessWidget {
  const CourtView({super.key, required this.feed, required this.you});

  final MatchFeed feed;
  final int you;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '試合のコート',
      child: ClipRect(child: FrameClock(builder: (context, time) => CustomPaint(size: Size.infinite, painter: _CourtPainter(feed, you, time)))),
    );
  }
}

class _CourtPainter extends CustomPainter {
  _CourtPainter(this.feed, this.you, this.time) : super(repaint: time);

  final MatchFeed feed;
  final int you;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final s = feed.latest;
    if (s == null) return;
    final k = size.width / Field.width;
    canvas.scale(k);
    final painter = s.game.painter;
    painter.paintCourt(canvas);
    final now = time.value;
    painter.paint(canvas, s.world, PaintInfo(you: you, time: now, phase: s.phase, server: s.server));
    // 得点した瞬間の着地点（IN / OUT）
    final lp = s.lastPoint;
    if (s.phase == MatchPhase.point && lp != null && lp.landX != null) {
      final x = clampD(lp.landX!, 20, Field.width - 20);
      ink(canvas, Sketch.circle(Offset(x, Field.ground + 2), 24, seed: 9), 3);
      drawText(canvas, lp.reason == 'アウト' ? 'OUT' : 'IN', Offset(x, Field.ground + 44), size: 22);
    }
    for (final b in feed.bursts) {
      b.draw(canvas, now);
    }
  }

  @override
  bool shouldRepaint(covariant _CourtPainter old) => true;
}

/// スコア（スマホ版 _ScoreBox: 自分は墨で塗った枠、相手は点線の枠。サーブ権はボールの印）
class _MatchHud extends StatelessWidget {
  const _MatchHud({required this.game});
  final GameKind game;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final model = s.model;
    final h = model.feed.hud;
    final serveShown = game.rules.serveRule != ServeRule.none;
    return Row(
      children: [
        DoodleIconButton(
          icon: Icons.close_rounded,
          label: '退出',
          onPressed: () async {
            final ok = await confirmDialog(context, message: '試合を抜けてタイトルに戻りますか？（相手の試合も終わります）', ok: '退出する');
            if (ok) model.leaveRoom();
          },
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ScoreBox(side: 0, you: model.you, score: h.score[0], serving: serveShown && h.server == 0, bar: h.extra?.bars[0], avatar: _avatarOf(model, 0)),
              SizedBox(
                width: 190,
                child: Column(
                  children: h.extra != null
                      ? [Text(h.extra!.center, style: const TextStyle(fontSize: 36, height: 1.1)), const Text('有効打の数', style: TextStyle(fontSize: 14))]
                      : [Text('PONG! ${game.title}', style: const TextStyle(fontSize: 18)), Text('${game.rules.winScore ?? 5}点先取', style: const TextStyle(fontSize: 14, color: Palette.pencil))],
                ),
              ),
              _ScoreBox(side: 1, you: model.you, score: h.score[1], serving: serveShown && h.server == 1, bar: h.extra?.bars[1], avatar: _avatarOf(model, 1)),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: s.settings,
          builder: (context, _) => DoodleIconButton(
            icon: s.settings.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            label: s.settings.soundOn ? '効果音をミュート' : '効果音をオン',
            onPressed: () => s.settings.soundOn = !s.settings.soundOn,
          ),
        ),
      ],
    );
  }
}

/// 部屋の情報から選手の見た目と名前を取り出す（スマホ版 avatarOf / playerNameOf）
Avatar _avatarOf(AppModel model, int side) => model.room?.players[side].look ?? Avatar.standard;

String _nameOf(AppModel model, int side) {
  final n = model.room?.players[side].name ?? '';
  return n.isEmpty ? (side == model.you ? 'あなた' : 'あいて') : n;
}

class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.side, required this.you, required this.score, required this.serving, required this.avatar, this.bar});

  final int side;
  final int you;
  final int score;
  final bool serving;
  final double? bar;
  final Avatar avatar;

  @override
  Widget build(BuildContext context) {
    final me = side == you;
    final fg = me ? Palette.paper : Palette.ink;
    final ball = SizedBox(width: 22, child: serving ? CustomPaint(size: const Size(16, 16), painter: _BallIcon(onDark: me)) : null);
    return Semantics(
      label: '${me ? 'あなた' : 'あいて'} $score点${serving ? '、サーブ' : ''}',
      child: CustomPaint(
        painter: SketchBorderPainter(seed: me ? 101 : 102, fillColor: me ? Palette.ink : Palette.paper, dashed: !me, shadow: false, strokeWidth: 2),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 16, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (side == 1) ball,
              AvatarIcon(avatar: avatar, size: 34, onDark: me),
              const SizedBox(width: 6),
              SizedBox(
                width: 110,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${me ? 'あなた' : 'あいて'}・${side == 0 ? '左' : '右'}', style: TextStyle(fontSize: 14, color: fg, height: 1.2)),
                    TweenAnimationBuilder<double>(
                      key: ValueKey(score),
                      tween: Tween(begin: 1.5, end: 1),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      builder: (context, k, child) => Transform.rotate(angle: (k - 1) * -0.2, child: Transform.scale(scale: k, child: child)),
                      child: Text('$score', style: TextStyle(fontSize: 38, color: fg, height: 1.05)),
                    ),
                    if (bar != null) _HpBar(value: bar!, onDark: me),
                  ],
                ),
              ),
              if (side == 0) ball,
            ],
          ),
        ),
      ),
    );
  }
}

/// サーブ権の印（白いボール）
class _BallIcon extends CustomPainter {
  _BallIcon({required this.onDark});
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, size.width / 2, Sketch.fill(Colors.white));
    canvas.drawCircle(c, size.width / 2, Sketch.pen(2, color: onDark ? Palette.paper : Palette.ink));
    if (onDark) canvas.drawCircle(c, size.width / 2 - 2, Sketch.pen(1.2));
  }

  @override
  bool shouldRepaint(covariant _BallIcon old) => old.onDark != onDark;
}

/// 体力ゲージ（斜線で塗る）
class _HpBar extends StatelessWidget {
  const _HpBar({required this.value, required this.onDark});
  final double value;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 200),
      builder: (context, v, _) => CustomPaint(size: const Size(100, 12), painter: _HpPainter(v, onDark)),
    );
  }
}

class _HpPainter extends CustomPainter {
  _HpPainter(this.value, this.onDark);
  final double value;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(1);
    final color = onDark ? Palette.paper : Palette.ink;
    final fill = Rect.fromLTWH(r.left, r.top, r.width * value.clamp(0, 1), r.height);
    Sketch.hatch(canvas, Path()..addRect(fill), fill, gap: 4, width: 1.6, color: color, seed: 5);
    canvas.drawPath(Sketch.rect(r, seed: 6, wobble: 0.6), Sketch.pen(1.6, color: color));
  }

  @override
  bool shouldRepaint(covariant _HpPainter old) => old.value != value || old.onDark != onDark;
}

/// 下部: 操作の案内。自分のサーブのときは強調する（スマホ版 _ControlStrip）
class _ControlStrip extends StatelessWidget {
  const _ControlStrip({required this.game});
  final GameKind game;

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    final h = model.feed.hud;
    final myServe = h.phase == MatchPhase.play && h.serving && h.server == model.you && h.resumeCount <= 0;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: CustomPaint(
        painter: SketchBorderPainter(seed: 111, dashed: !myServe, shadow: false, fillColor: myServe ? Palette.ink : Palette.paper, strokeWidth: 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Center(
          child: myServe
              ? const Text('あなたのサーブ！ J で打つ', style: TextStyle(fontSize: 22, color: Palette.paper))
              : Wrap(
                  spacing: 18,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final c in game.controls)
                      Row(mainAxisSize: MainAxisSize.min, children: [Keycap(c.key, size: 13), const SizedBox(width: 6), Text(c.label, style: const TextStyle(fontSize: 15))]),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

/// コートの上に重ねる表示: 開始前の操作説明、得点、一時停止、再開カウントダウン
class _Overlays extends StatelessWidget {
  const _Overlays({required this.game});
  final GameKind game;

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    final h = model.feed.hud;
    Widget sheet(List<Widget> children, int seed) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: DoodleBox(seed: seed, shadow: true, padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, children: children)),
          ),
        );
    if (h.paused) {
      final opp = model.room?.opponent;
      return sheet([
        const Text('一時停止中', style: TextStyle(fontSize: 30)),
        const SizedBox(height: 10),
        if (opp != null && opp.present && !opp.connected) ...[
          const Text('相手の通信が切れました。自動でつなぎ直すのを待っています。', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, height: 1.45)),
          if (model.oppGoneAt != null) Countdown(since: model.oppGoneAt!, builder: (left) => Text('あと $left 秒', style: const TextStyle(fontSize: 18))),
          const SizedBox(height: 4),
          const Text('つながり直すと 同じところから再開します。', style: TextStyle(fontSize: 15, color: Palette.pencil)),
          const SizedBox(height: 14),
          SizedBox(width: 260, child: DoodleButton(label: '退出してタイトルへ', seed: 124, onPressed: model.leaveRoom)),
        ] else
          const Text('通信を確認しています…', style: TextStyle(fontSize: 18)),
      ], 123);
    }
    if (h.resumeCount > 0) {
      return sheet([const Text('つながりました。再開まで', style: TextStyle(fontSize: 22)), Text('${h.resumeCount}', style: const TextStyle(fontSize: 96, height: 1.1))], 121);
    }
    if (h.phase == MatchPhase.intro) {
      return sheet([
        Text('PONG! ${game.title}', style: const TextStyle(fontSize: 30)),
        const SizedBox(height: 6),
        Text('あなたは${model.you == 0 ? '左' : '右'}の選手（太い線・「あなた」）', style: const TextStyle(fontSize: 17)),
        Text(game.ruleText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Palette.pencil)),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Fighter(avatar: _avatarOf(model, 0), name: _nameOf(model, 0), caption: '${model.you == 0 ? 'あなた' : 'あいて'}・左'),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('VS', style: TextStyle(fontSize: 26))),
            _Fighter(avatar: _avatarOf(model, 1), name: _nameOf(model, 1), caption: '${model.you == 1 ? 'あなた' : 'あいて'}・右'),
          ],
        ),
        const SizedBox(height: 8),
        ControlsList(controls: game.controls, size: 17),
        Text('${math.max(1, h.count)}', style: const TextStyle(fontSize: 72, height: 1.1)),
      ], 122);
    }
    final lp = h.lastPoint;
    if (h.phase == MatchPhase.point && lp != null) {
      final mine = lp.side == model.you;
      final title = lp.side == null ? '${lp.reason}！' : (mine ? 'あなたの得点！' : 'あいての得点');
      final sub = lp.side == null ? '得点なし' : lp.reason;
      return Align(
        alignment: const Alignment(0, -0.7),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(lp.n),
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          builder: (context, k, child) => Transform.rotate(angle: -0.035, child: Transform.scale(scale: k, child: child)),
          child: CustomPaint(
            painter: SketchBorderPainter(seed: 130, fillColor: mine ? Palette.ink : Palette.paper),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 32, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: TextStyle(fontSize: 32, color: mine ? Palette.paper : Palette.ink)),
                Text(sub, style: TextStyle(fontSize: 16, color: mine ? Palette.paper : Palette.ink)),
              ]),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 結果画面
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    final r = model.room;
    if (r == null) return const DoodleScaffold(showBack: false, child: SizedBox.shrink());
    final h = model.feed.hud;
    final me = r.me, opp = r.opponent;
    final won = h.winner == r.you;
    final title = h.winner == -1 ? '引き分け' : (won ? 'あなたの勝ち！' : 'あいての勝ち');
    // 記号の形（●/×）と文字で状態を示す（StatusLine と同じ考え方。中央にそろえるため Text で組む）
    final Widget status = switch ((opp.present, opp.connected, me.rematch, opp.rematch)) {
      (false, _, _, _) => const Text('×  相手は退出しました', style: TextStyle(fontSize: 17)),
      (_, false, _, _) => const Text('×  相手の通信が切れています。つなぎ直すのを待っています…', style: TextStyle(fontSize: 17)),
      (_, _, true, false) => const Row(mainAxisSize: MainAxisSize.min, children: [DoodleSpinner(size: 20), SizedBox(width: 10), Text('相手が「もう一度」を押すのを待っています', style: TextStyle(fontSize: 17))]),
      (_, _, false, true) => const Text('●  あいては もう一度 やりたがっています', style: TextStyle(fontSize: 17)),
      _ => const SizedBox.shrink(),
    };
    return DoodleScaffold(
      showBack: false,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PONG! ${r.game.title}', style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              Transform.rotate(angle: -0.035, child: Text(title, style: const TextStyle(fontSize: 60, height: 1.2))),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _FinalScore(label: '${_nameOf(model, 0)}・左', score: h.score[0], isMe: r.you == 0, avatar: r.players[0].look, mood: _mood(h.winner, 0)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('-', style: TextStyle(fontSize: 48))),
                  _FinalScore(label: '${_nameOf(model, 1)}・右', score: h.score[1], isMe: r.you == 1, avatar: r.players[1].look, mood: _mood(h.winner, 1)),
                ],
              ),
              Text('${h.endReason ?? ''}${r.game.scoreUnit == null ? '' : '（${r.game.scoreUnit}の数）'}', style: const TextStyle(fontSize: 18, color: Palette.pencil)),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 220, child: DoodleButton(label: 'タイトルへ', seed: 171, onPressed: model.leaveRoom)),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 280,
                    child: DoodleButton(
                      label: me.rematch ? '相手を待っています…' : 'もう一度',
                      icon: Icons.refresh_rounded,
                      primary: true,
                      seed: 170,
                      onPressed: me.rematch || !opp.connected ? null : model.rematch,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(height: 32, child: Center(child: status)),
            ],
          ),
        ),
      ),
    );
  }
}

AvatarMood _mood(int? winner, int side) => winner == null || winner == -1 ? AvatarMood.normal : (winner == side ? AvatarMood.win : AvatarMood.lose);

/// 試合前の「VS」に並べる選手（スマホ版 _Fighter）
class _Fighter extends StatelessWidget {
  const _Fighter({required this.avatar, required this.name, required this.caption});
  final Avatar avatar;
  final String name;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        children: [
          AvatarView(avatar: avatar, size: 64),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
          Text(caption, style: const TextStyle(fontSize: 13, color: Palette.pencil, height: 1)),
        ],
      ),
    );
  }
}

class _FinalScore extends StatelessWidget {
  const _FinalScore({required this.label, required this.score, required this.isMe, required this.avatar, required this.mood});
  final String label;
  final int score;
  final bool isMe;
  final Avatar avatar;
  final AvatarMood mood;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      AvatarView(avatar: avatar, size: 110, mood: mood),
      Text(label, style: const TextStyle(fontSize: 17)),
      Text('$score', style: TextStyle(fontSize: 64, height: 1.1, decoration: isMe ? TextDecoration.underline : null)),
    ]);
  }
}
