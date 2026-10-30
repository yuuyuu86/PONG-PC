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
          const Text('あそぶ競技をえらんでください。部屋ができたら、4文字のコードを相手に伝えるか、紙飛行機で招待します。あなたが左の選手になります。', style: TextStyle(fontSize: 18, height: 1.45)),
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
                      child: GameCard(game: g, seed: 20 + i, onTap: model.busy ? () {} : () => model.createRoom(g)),
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
                      child: StatusLine(state: StatusKind.waiting, text: '部屋を探しています…（相手に「部屋を作る」を押してもらってください）'),
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
