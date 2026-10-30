import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../app/feedback.dart';
import '../avatar/avatar.dart';
import '../avatar/avatar_editor.dart';
import '../avatar/avatar_painter.dart';
import '../app/services.dart';
import '../games/core/catalog.dart';
import '../games/core/common.dart';
import '../games/core/match.dart';
import '../games/core/painting.dart';
import '../net/discovery.dart';
import '../ui/doodle.dart';
import '../ui/logo.dart';
import '../ui/widgets.dart';
import 'root.dart';

/// ゲーム集トップ。左に参加のしかた、真ん中に自分の棒人間、右に近くのPCとメニュー。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _figure = GlobalKey();
  Offset _look = Offset.zero;

  /// カーソルの位置から、棒人間の見る向き（-1〜1）を決める
  void _hover(PointerEvent e) {
    final box = _figure.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // 顔は上から 1/4 あたり
    final eyes = box.localToGlobal(Offset(box.size.width / 2, box.size.height * 0.25));
    final d = e.position - eyes;
    final look = d / (d.distance + 160);
    if ((look - _look).distance > 0.01) setState(() => _look = look);
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final model = s.model;
    final modes = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModeCard(
          label: '部屋を作る',
          caption: '競技をえらんで 相手を待つ',
          icon: Icons.add_home_rounded,
          primary: true,
          seed: 41,
          tilt: -0.025,
          onPressed: () => model.go(Screen.create),
        ),
        const SizedBox(height: 26),
        ModeCard(
          label: 'コードで参加',
          caption: '相手の 4文字コードを入れる',
          icon: Icons.keyboard_rounded,
          seed: 42,
          tilt: 0.02,
          onPressed: () {
            model.joinMessage = null;
            model.go(Screen.join);
          },
        ),
        const SizedBox(height: 26),
        ListenableBuilder(
          listenable: model.discovery,
          builder: (context, _) {
            final rooms = model.discovery.peers.where((p) => p.state == PeerState.host && p.code != null).toList();
            return ModeCard(
              label: '近くの部屋',
              caption: rooms.isEmpty ? '同じWi-Fiの部屋を さがし中…' : rooms.map((p) => '${p.name}（${p.game?.title ?? '?'}）').join('、'),
              icon: Icons.wifi_tethering_rounded,
              badge: rooms.isEmpty ? null : '${rooms.length}',
              seed: 43,
              tilt: -0.015,
              onPressed: () {
                model.joinMessage = null;
                model.go(Screen.nearby);
              },
            );
          },
        ),
      ],
    );
    final figure = ListenableBuilder(
      listenable: s.settings,
      builder: (context, _) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: 0.75,
              child: Stack(
                key: _figure,
                fit: StackFit.expand,
                children: [
                  const CustomPaint(painter: _FloorPainter()),
                  LayoutBuilder(builder: (context, c) => Center(child: AvatarView(avatar: s.settings.avatar, size: c.maxHeight, look: _look))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(s.settings.playerName, style: const TextStyle(fontSize: 26)),
        ],
      ),
    );
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const _NearbyPanel(),
        const SizedBox(height: 18),
        for (final (i, (label, icon, screen)) in const [
          ('あそびかた', Icons.menu_book_rounded, Screen.howto),
          ('プロフィール', Icons.person_outline_rounded, Screen.profile),
          ('設定', Icons.tune_rounded, Screen.settings),
        ].indexed)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: 230, child: DoodleButton(label: label, icon: icon, seed: 31 + i, fontSize: 18, onPressed: () => model.go(screen))),
            ),
          ),
      ],
    );
    const logo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PongLogo(fontSize: 64),
        Text('PC 2台で あそぶ 1たい1', style: TextStyle(fontSize: 18)),
      ],
    );
    return DoodleScaffold(
      showBack: false,
      child: MouseRegion(
        onHover: _hover,
        child: LayoutBuilder(builder: (context, c) {
          // 狭いウィンドウや大きな文字では、上から順に並べてスクロールする
          if (c.maxWidth < 900 || c.maxHeight < 560 || MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return PageBody(children: [logo, side, const SizedBox(height: 24), modes, const SizedBox(height: 24), SizedBox(height: 320, child: figure)]);
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: c.maxWidth * 0.32,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      logo,
                      const SizedBox(height: 16),
                      // 看板: 2本の棒を地面まで立て、その上に札をかける
                      Expanded(
                        child: Stack(
                          children: [
                            const Positioned.fill(child: CustomPaint(painter: _PostPainter())),
                            SingleChildScrollView(padding: const EdgeInsets.only(top: 12, bottom: 40), child: modes),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: figure)),
                SizedBox(width: c.maxWidth * 0.28, child: SingleChildScrollView(child: side)),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// 左に並ぶ大きな札（参加のしかた）。少し傾けて、カーソルを乗せると持ち上がる。
class ModeCard extends StatefulWidget {
  const ModeCard({super.key, required this.label, required this.caption, required this.icon, required this.onPressed, this.primary = false, this.seed = 1, this.tilt = 0, this.badge});

  final String label;
  final String caption;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final int seed;
  final double tilt;
  final String? badge;

  @override
  State<ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<ModeCard> {
  bool _hot = false;
  bool _focused = false;

  void _activate() {
    Services.of(context).feedback.play(Sound.tap);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.primary ? Palette.paper : Palette.ink;
    return Semantics(
      button: true,
      label: '${widget.label}。${widget.caption}',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hot = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _activate();
            return null;
          }),
        },
        child: GestureDetector(
          onTap: _activate,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: _hot || _focused ? 1.04 : 1,
            child: Transform.rotate(
              angle: widget.tilt,
              child: CustomPaint(
                painter: SketchBorderPainter(seed: widget.seed, fillColor: widget.primary ? Palette.ink : Palette.paper, strokeWidth: _focused ? 4.2 : 2.8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 24, 18),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: fg, width: 2.6)),
                        child: Icon(widget.icon, size: 34, color: fg),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(child: Text(widget.label, style: TextStyle(fontSize: 32, height: 1.1, color: fg))),
                                if (widget.badge != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
                                    decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(14)),
                                    child: Text(widget.badge!, style: TextStyle(fontSize: 17, color: widget.primary ? Palette.ink : Palette.paper)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(widget.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: fg)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 看板の2本の棒（札の後ろを通って地面まで）と、足もとの草
class _PostPainter extends CustomPainter {
  const _PostPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ground = size.height - 6;
    final pen = Sketch.pen(2.6);
    for (final (i, x) in [size.width * 0.22, size.width * 0.72].indexed) {
      for (final dx in [-7.0, 7.0]) {
        canvas.drawPath(Sketch.line(Offset(x + dx, 20), Offset(x + dx, ground), seed: 80 + i * 2 + (dx > 0 ? 1 : 0)), pen);
      }
      // 根元の草
      for (final k in [-1.0, 1.0]) {
        canvas.drawPath(Sketch.line(Offset(x + k * 12, ground), Offset(x + k * 20, ground - 12), seed: 90 + i), Sketch.pen(1.8));
      }
    }
    canvas.drawPath(Sketch.line(Offset(0, ground), Offset(size.width, ground), seed: 95), Sketch.pen(2, color: Palette.pencil));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 棒人間の足もとの床（だ円の影と、手描きの線）
class _FloorPainter extends CustomPainter {
  const _FloorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.93);
    canvas.drawOval(Rect.fromCenter(center: c, width: size.width * 0.7, height: size.height * 0.07), Sketch.fill(Palette.faint));
    final pen = Sketch.pen(1.6, color: Palette.pencil);
    for (var i = 0; i < 3; i++) {
      final y = c.dy + size.height * (0.025 + i * 0.02);
      final w = size.width * (0.4 - i * 0.1);
      canvas.drawPath(Sketch.line(Offset(c.dx - w, y), Offset(c.dx + w, y), seed: 60 + i), pen);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 右側: 同じWi-Fiにいる PONG! の一覧
class _NearbyPanel extends StatelessWidget {
  const _NearbyPanel();

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    final d = model.discovery;
    return DoodleBox(
      seed: 70,
      child: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          final peers = d.peers;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DoodleHeading('近くの PONG!', size: 20),
              const SizedBox(height: 8),
              if (d.status == DiscoveryStatus.failed || model.listenError != null)
                StatusLine(state: StatusKind.bad, text: '近くのPCを探せません（ポート ${d.udpPort} が使われているか、ファイアウォールで止められています）')
              else if (peers.isEmpty)
                const StatusLine(state: StatusKind.waiting, text: '同じWi-Fiの PONG! を探しています…')
              else
                for (final p in peers.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        AvatarIcon(avatar: Avatar.decode(p.avatar), size: 34),
                        const SizedBox(width: 10),
                        Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18))),
                        Text(
                          switch (p.state) {
                            PeerState.host => '部屋あり',
                            PeerState.full => '満員',
                            PeerState.busy => '試合中',
                            PeerState.idle => 'まちぼうけ',
                          },
                          style: const TextStyle(fontSize: 15, color: Palette.pencil),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// 近くの PONG! の見つかり具合（●/○/×）
class NearbyStatus extends StatelessWidget {
  const NearbyStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final d = s.model.discovery;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          final name = s.settings.playerName;
          if (d.status == DiscoveryStatus.failed || s.model.listenError != null) {
            return StatusLine(state: StatusKind.bad, text: '近くのPCを探せません（ほかのアプリがポート ${d.udpPort} を使っているか、ファイアウォールで止められています）');
          }
          final peers = d.peers;
          if (peers.isEmpty) return StatusLine(state: StatusKind.waiting, text: '同じWi-Fiの PONG! を探しています…（あなたは「$name」）');
          return StatusLine(state: StatusKind.ok, text: '同じWi-Fiの PONG!: ${peers.map((p) => p.name).join('、')}（あなたは「$name」）');
        },
      ),
    );
  }
}

/// ゲーム選択カード。コートの縮小図を手描き風に描く。
class GameCard extends StatelessWidget {
  const GameCard({super.key, required this.game, required this.onTap, this.seed = 1});

  final GameKind game;
  final VoidCallback onTap;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${game.title}。${game.tagline}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            Services.of(context).feedback.play(Sound.tap);
            onTap();
          },
          child: CustomPaint(
            painter: SketchBorderPainter(seed: seed),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(aspectRatio: 16 / 7, child: CourtThumbnail(game: game)),
                  const SizedBox(height: 6),
                  Text(game.title, style: const TextStyle(fontSize: 30, height: 1.1)),
                  const SizedBox(height: 4),
                  Text(game.tagline, style: const TextStyle(fontSize: 17)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final c in game.controls.take(3)) Padding(padding: const EdgeInsets.only(right: 8), child: Keycap(c.key, size: 13)),
                      const Spacer(),
                      const Text('えらぶ →', style: TextStyle(fontSize: 19)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CourtThumbnail extends StatelessWidget {
  const CourtThumbnail({super.key, required this.game});
  final GameKind game;

  @override
  Widget build(BuildContext context) => ClipRect(child: CustomPaint(size: Size.infinite, painter: _ThumbPainter(game)));
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.game);
  final GameKind game;

  @override
  void paint(Canvas canvas, Size size) {
    // コートの中央付近を切り出して、選手が見える大きさにする
    const viewW = Field.width * 0.86;
    final k = size.width / viewW;
    final top = Field.height - viewW * size.height / size.width;
    canvas
      ..scale(k)
      ..translate(-(Field.width - viewW) / 2, -top);
    final rules = game.rules;
    final world = rules.makeWorld();
    rules.serve(world, 0);
    game.painter
      ..paintCourt(canvas)
      ..paint(canvas, world, const PaintInfo(you: -1, time: 0, phase: MatchPhase.intro, server: 0));
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) => old.game != game;
}
