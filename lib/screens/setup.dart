import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_model.dart';
import '../app/services.dart';
import '../games/core/catalog.dart';
import '../net/discovery.dart';
import '../net/wire.dart';
import '../ui/doodle.dart';
import '../ui/widgets.dart';
import 'root.dart';

/// 選んだゲームの対戦準備: 部屋を作る / コードで参加 / 近くの部屋
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.game});
  final GameKind game;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _code = TextEditingController();
  int _tab = 0;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    final g = widget.game;
    final msg = model.joinMessage;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${g.summary}\n${g.ruleText}', style: const TextStyle(fontSize: 18, height: 1.5)),
        const SizedBox(height: 16),
        DoodleBox(
          seed: 60,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const DoodleHeading('そうさ（2台とも同じキー）', size: 19), const SizedBox(height: 8), ControlsList(controls: g.controls)],
          ),
        ),
      ],
    );
    // 参加のしかたはタブで切り替える（スマホ版と同じ）
    final connect = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DoodleTabs(labels: const ['部屋を作る', 'コードで参加'], selected: _tab, seed: 44, onChanged: (i) => setState(() => _tab = i)),
        const SizedBox(height: 20),
        if (_tab == 0) ...[
          const Text('部屋を作ると 4文字のコードが出ます。そのコードを相手に伝えるか、紙飛行機で招待してください。あなたが左の選手になります。',
              style: TextStyle(fontSize: 17, height: 1.45)),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 280,
              child: DoodleButton(
                label: '部屋を作る',
                subtitle: 'コードを相手に伝える',
                icon: Icons.add_home_rounded,
                primary: true,
                seed: 41,
                onPressed: model.busy ? null : () => model.createRoom(g),
              ),
            ),
          ),
        ] else ...[
          const Text('相手の画面に出ている英字4文字を入れてください。あなたが右の選手になります。', style: TextStyle(fontSize: 17, height: 1.45)),
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
              SizedBox(width: 130, child: DoodleButton(label: '参加', icon: Icons.login_rounded, seed: 42, onPressed: model.busy ? null : () => model.join(_code.text))),
            ],
          ),
          const SizedBox(height: 22),
          const NearbyRooms(),
        ],
        if (msg != null) ...[
          const SizedBox(height: 18),
          DoodleBox(
            seed: 63,
            dashed: !msg.error,
            child: Row(
              children: [
                if (!msg.error) ...[const DoodleSpinner(size: 20), const SizedBox(width: 10)],
                Expanded(child: StatusLine(state: msg.error ? StatusKind.bad : StatusKind.waiting, text: msg.text)),
              ],
            ),
          ),
        ],
      ],
    );
    return DoodleScaffold(
      title: 'PONG! ${g.title}',
      onBack: () {
        model.joinMessage = null;
        model.go(Screen.home);
      },
      child: PageBody(
        children: [
          // 狭いウィンドウや大きな文字では縦に並べる
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 760 || MediaQuery.textScalerOf(context).scale(1) > 1.3) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [connect, const SizedBox(height: 22), info]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: info), const SizedBox(width: 32), Expanded(child: connect)]);
          }),
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
    return TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
  }
}

/// 同じWi-Fiで相手を待っている部屋（ワンクリックで参加）
class NearbyRooms extends StatelessWidget {
  const NearbyRooms({super.key});

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return ListenableBuilder(
      listenable: model.discovery,
      builder: (context, _) {
        final rooms = model.discovery.peers.where((p) => p.state == PeerState.host && p.code != null).toList();
        if (rooms.isEmpty) return const SizedBox.shrink();
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
                    Expanded(child: StatusLine(state: StatusKind.ok, text: '${p.name} の部屋　${p.game == null ? '' : 'PONG! ${p.game!.title}'}　コード ${p.code}')),
                    SizedBox(width: 150, child: DoodleButton(label: '参加する', seed: 64, fontSize: 17, onPressed: model.busy ? null : () => model.join(p.code!))),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
