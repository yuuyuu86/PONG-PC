import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_model.dart';
import '../app/services.dart';
import '../games/core/catalog.dart';
import '../net/discovery.dart';
import '../net/wire.dart';
import '../ui/doodle.dart';
import '../ui/widgets.dart';
import 'home.dart';
import 'root.dart';

/// 部屋を作る: 競技を選ぶと、その競技の部屋ができる
class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return DoodleScaffold(
      title: '部屋を作る',
      onBack: () => model.go(Screen.home),
      child: PageBody(
        maxWidth: 980,
        children: [
          const Text('あそぶ競技をえらんでください。部屋ができたら、4文字のコードを相手に伝えます。あなたが左の選手になります。', style: TextStyle(fontSize: 18, height: 1.45)),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, c) {
              final two = c.maxWidth > 700;
              final w = two ? (c.maxWidth - 22) / 2 : c.maxWidth;
              return Wrap(
                spacing: 22,
                runSpacing: 22,
                children: [
                  for (final (i, g) in GameKind.values.indexed)
                    SizedBox(
                      width: w,
                      child: GameCard(game: g, seed: 20 + i, onTap: model.busy ? () {} : () => _pickRule(context, g)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 競技を選んだあと、ルールを選んで部屋を作る
Future<void> _pickRule(BuildContext context, GameKind game) async {
  final model = Services.of(context).model;
  final rule = await showDialog<int>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (ctx) => _RuleDialog(game: game),
  );
  if (rule != null) model.createRoom(game, rule: rule);
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.game});
  final GameKind game;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late int _rule = widget.game.defaultRule;

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final choices = g.ruleChoices;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DoodleBox(
          shadow: true,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DoodleHeading('PONG! ${g.title} のルール', size: 22),
              const SizedBox(height: 14),
              Text(g == GameKind.boxing ? '試合時間' : '何点で勝ち？', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              DoodleTabs(labels: [for (final c in choices) g.ruleLabel(c)], selected: choices.indexOf(_rule), seed: 210, onChanged: (i) => setState(() => _rule = choices[i])),
              const SizedBox(height: 12),
              Text(g.ruleTextFor(_rule), style: const TextStyle(fontSize: 16, color: Palette.pencil, height: 1.4)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: DoodleButton(label: 'やめる', fontSize: 19, seed: 211, onPressed: () => Navigator.pop(context))),
                  const SizedBox(width: 14),
                  Expanded(child: DoodleButton(label: '部屋を作る', icon: Icons.add_home_rounded, fontSize: 19, primary: true, seed: 212, onPressed: () => Navigator.pop(context, _rule))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// コードで参加 / 近くの部屋に参加（[nearby] なら近くの部屋の一覧だけ）
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, this.nearby = false});
  final bool nearby;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    final msg = model.joinMessage;
    return DoodleScaffold(
      title: widget.nearby ? '近くの部屋' : 'コードで参加',
      onBack: () {
        model.joinMessage = null;
        model.go(Screen.home);
      },
      child: PageBody(
        maxWidth: 760,
        children: [
          if (widget.nearby) ...[
            const Text('同じWi-Fiで相手を待っている部屋です。押すとその部屋に参加します。あなたが右の選手になります。', style: TextStyle(fontSize: 18, height: 1.45)),
            const SizedBox(height: 16),
            const SideBySideHint(you: 1),
            const SizedBox(height: 22),
            const NearbyRooms(showEmpty: true),
          ] else ...[
            const Text('相手の画面に出ている英字4文字を入れてください。あなたが右の選手になります。', style: TextStyle(fontSize: 18, height: 1.45)),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 190,
                  child: TextField(
                    controller: _code,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 34, letterSpacing: 8),
                    inputFormatters: [_CodeFormatter()],
                    decoration: const InputDecoration(
                      hintText: 'ABCD',
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Palette.ink, width: 2.4)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Palette.ink, width: 3)),
                    ),
                    onSubmitted: model.busy ? null : (v) => model.join(v),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 130,
                  child: DoodleButton(label: '参加', icon: Icons.login_rounded, seed: 42, onPressed: model.busy ? null : () => model.join(_code.text)),
                ),
              ],
            ),
          ],
          if (msg != null) ...[
            const SizedBox(height: 18),
            DoodleBox(
              seed: 63,
              dashed: !msg.error,
              child: Row(
                children: [
                  if (!msg.error) ...[const DoodleSpinner(size: 20), const SizedBox(width: 10)],
                  Expanded(
                    child: StatusLine(state: msg.error ? StatusKind.bad : StatusKind.waiting, text: msg.text),
                  ),
                ],
              ),
            ),
          ],
          if (!widget.nearby) ...[const SizedBox(height: 26), const NearbyRooms()],
        ],
      ),
    );
  }
}

class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = RoomCode.normalize(newValue.text);
    final v = t.length > 4 ? t.substring(0, 4) : t;
    return TextEditingValue(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
  }
}

/// 同じWi-Fiで相手を待っている部屋（ワンクリックで参加）
class NearbyRooms extends StatelessWidget {
  const NearbyRooms({super.key, this.showEmpty = false});

  /// 部屋がないときも「探しています」と出す
  final bool showEmpty;

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return ListenableBuilder(
      listenable: model.discovery,
      builder: (context, _) {
        final rooms = model.discovery.peers.where((p) => p.state == PeerState.host && p.code != null).toList();
        if (rooms.isEmpty) {
          return showEmpty
              ? const Row(
                  children: [
                    DoodleSpinner(size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('部屋を探しています…（相手に「部屋を作る」を押してもらってください）', style: TextStyle(fontSize: 17)),
                    ),
                  ],
                )
              : const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DoodleHeading('近くで相手を待っている部屋', size: 19),
            const SizedBox(height: 10),
            for (final p in rooms)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: StatusLine(state: StatusKind.ok, text: '${p.name} の部屋　${p.game == null ? '' : 'PONG! ${p.game!.title}'}　コード ${p.code}'),
                    ),
                    SizedBox(
                      width: 150,
                      child: DoodleButton(label: '参加する', seed: 64, fontSize: 17, onPressed: model.busy ? null : () => model.join(p.code!)),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
