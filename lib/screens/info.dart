import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../app/feedback.dart';
import '../app/services.dart';
import '../games/core/catalog.dart';
import '../ui/doodle.dart';
import '../ui/widgets.dart';
import 'root.dart';

/// あそびかた。「はじめかた」と競技ごとのタブに分ける（スマホ版と同じ）。
class HowToScreen extends StatefulWidget {
  const HowToScreen({super.key});

  @override
  State<HowToScreen> createState() => _HowToScreenState();
}

class _HowToScreenState extends State<HowToScreen> {
  int _tab = 0;

  static const _steps = [
    '2台のPC（Mac / Windows どちらでも）を同じWi-Fiにつなぎ、両方で PONG! を開きます。サーバーの準備は要りません。',
    '遊びたいゲームを選び、片方が「部屋を作る」。部屋を作った人が左、参加した人が右の選手です。',
    '相手のPCを右に並べて「紙飛行機で招待」すると、紙飛行機が画面をまたいで飛んでいき、相手の画面に招待状が届きます。',
    'または、画面に出た4文字の部屋コードを伝えて、相手が「コードで参加」。',
    '2人とも「準備OK」を押すと、操作説明のあと試合開始。各自のキーボードで操作します。',
  ];

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return DoodleScaffold(
      title: 'あそびかた',
      onBack: () => model.go(Screen.home),
      child: PageBody(
        children: [
          DoodleTabs(
            labels: ['はじめかた', for (final g in GameKind.values) g.title],
            selected: _tab,
            seed: 150,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 20),
          if (_tab > 0)
            _GameRules(game: GameKind.values[_tab - 1])
          else ...[
            const DoodleHeading('はじめかた', size: 21),
            const SizedBox(height: 10),
            for (final (i, s) in _steps.indexed)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${i + 1}. $s', style: const TextStyle(fontSize: 17, height: 1.45))),
            const SizedBox(height: 6),
            const Text('どちらの画面にもコート全体が同じ向きで見えます。自分の選手は太い線と、墨で塗った「あなた」の名札、相手は点線の名札「あいて」で見分けられます。',
                style: TextStyle(fontSize: 16, height: 1.45)),
            const SizedBox(height: 6),
            const Text('通信が切れたら試合は自動で止まり、つながり直すと同じところから続きます。', style: TextStyle(fontSize: 16, height: 1.45)),
          ],
        ],
      ),
    );
  }
}

/// 競技ごとのタブの中身: 特徴・ルール・操作
class _GameRules extends StatelessWidget {
  const _GameRules({required this.game});
  final GameKind game;

  @override
  Widget build(BuildContext context) {
    return DoodleBox(
      seed: 71 + game.index,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DoodleHeading('PONG! ${game.title}', size: 21),
          const SizedBox(height: 8),
          Text(game.summary, style: const TextStyle(fontSize: 17, height: 1.45)),
          const SizedBox(height: 6),
          Text(game.ruleText, style: const TextStyle(fontSize: 16, color: Palette.pencil)),
          const SizedBox(height: 14),
          const DoodleHeading('そうさ（2台とも同じキー）', size: 18),
          const SizedBox(height: 8),
          ControlsList(controls: game.controls, size: 16),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return DoodleScaffold(
      title: '設定',
      onBack: () => s.model.go(Screen.home),
      child: PageBody(
        maxWidth: 680,
        children: [
          DoodleBox(
            seed: 82,
            child: ListenableBuilder(
              listenable: s.settings,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DoodleHeading('効果音', size: 21),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 170,
                        child: DoodleButton(
                          label: s.settings.soundOn ? '音 ON' : '音 OFF',
                          icon: s.settings.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                          primary: s.settings.soundOn,
                          seed: 83,
                          fontSize: 18,
                          onPressed: () => s.settings.soundOn = !s.settings.soundOn,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text('音量', style: TextStyle(fontSize: 18)),
                      SizedBox(
                        width: 260,
                        child: Slider(value: s.settings.volume, onChanged: (v) => s.settings.volume = v, onChangeEnd: (_) => s.feedback.play(Sound.hit)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
