import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../app/feedback.dart';
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

/// ゲーム集トップ
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return DoodleScaffold(
      showBack: false,
      leading: DoodleIconButton(
        icon: Icons.tune_rounded,
        label: '設定',
        onPressed: () => model.go(Screen.settings),
      ),
      actions: [
        DoodleIconButton(
          icon: Icons.person_outline_rounded,
          label: 'プロフィール',
          onPressed: () => model.go(Screen.profile),
        ),
      ],
      child: PageBody(
        maxWidth: 980,
        children: [
          const Center(child: PongLogo(fontSize: 96)),
          const Text('PC 2台で あそぶ 1たい1', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
          const SizedBox(height: 10),
          const Center(child: NearbyStatus()),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, c) {
            final two = c.maxWidth > 700;
            final w = two ? (c.maxWidth - 22) / 2 : c.maxWidth;
            return Wrap(
              spacing: 22,
              runSpacing: 22,
              children: [
                for (final (i, g) in GameKind.values.indexed)
                  SizedBox(width: w, child: GameCard(game: g, seed: 20 + i, onTap: () => model.go(Screen.setup, game: g))),
              ],
            );
          }),
          const SizedBox(height: 24),
          Center(child: SizedBox(width: 220, child: DoodleButton(label: 'あそびかた', icon: Icons.menu_book_rounded, seed: 31, fontSize: 19, onPressed: () => model.go(Screen.howto)))),
        ],
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
