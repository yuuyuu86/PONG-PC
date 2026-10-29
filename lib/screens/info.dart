import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../app/feedback.dart';
import '../app/services.dart';
import '../app/settings.dart';
import '../games/core/catalog.dart';
import '../ui/doodle.dart';
import '../ui/widgets.dart';
import 'room.dart';
import 'root.dart';

class HowToScreen extends StatelessWidget {
  const HowToScreen({super.key});

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
          DoodleBox(
            seed: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DoodleHeading('2台で遊ぶ', size: 21),
                const SizedBox(height: 8),
                for (final (i, s) in _steps.indexed)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('${i + 1}. $s', style: const TextStyle(fontSize: 17, height: 1.45))),
              ],
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth > 700 ? (c.maxWidth - 18) / 2 : c.maxWidth;
            return Wrap(
              spacing: 18,
              runSpacing: 18,
              children: [
                for (final g in GameKind.values)
                  SizedBox(
                    width: w,
                    child: DoodleBox(
                      seed: 71 + g.index,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DoodleHeading('PONG! ${g.title}', size: 20),
                          const SizedBox(height: 8),
                          ControlsList(controls: g.controls, size: 15),
                          const SizedBox(height: 6),
                          Text(g.ruleText, style: const TextStyle(fontSize: 15, color: Palette.pencil)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 16),
          const Text('どちらの画面にもコート全体が同じ向きで見えます。自分の選手は太い線と、墨で塗った「あなた」の名札で表示されます。',
              style: TextStyle(fontSize: 16, color: Palette.pencil)),
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
  late final _name = TextEditingController(text: Services.of(context).settings.playerName);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final settings = Services.of(context).settings;
    final err = AppSettings.validateName(_name.text);
    setState(() => _error = err);
    if (err == null) settings.playerName = _name.text;
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return DoodleScaffold(
      title: '設定',
      onBack: () {
        _save();
        s.model.go(Screen.home);
      },
      child: PageBody(
        children: [
          DoodleBox(
            seed: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DoodleHeading('なまえ と みため', size: 21),
                const SizedBox(height: 8),
                const Text('近くのPCの一覧や招待状、部屋に出ます。', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 300,
                      child: TextField(
                        controller: _name,
                        maxLength: AppSettings.maxNameLength,
                        style: const TextStyle(fontSize: 24),
                        decoration: InputDecoration(
                          errorText: _error,
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Palette.ink, width: 2.4)),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Palette.ink, width: 3)),
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(width: 120, child: DoodleButton(label: '保存', seed: 81, fontSize: 18, onPressed: _save)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 150,
                      child: DoodleButton(
                        label: 'おまかせ',
                        seed: 84,
                        fontSize: 18,
                        onPressed: () {
                          _name.text = AppSettings.suggestName();
                          _save();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const ProfileEditor(),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
