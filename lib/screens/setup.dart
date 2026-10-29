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
    return DoodleScaffold(
      title: 'PONG! ${g.title}',
      onBack: () {
        model.joinMessage = null;
        model.go(Screen.home);
      },
      child: PageBody(
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
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DoodleHeading('部屋を作る', size: 21),
                    const SizedBox(height: 8),
                    const Text('あなたが左の選手になります。コードを伝えるか、紙飛行機で招待できます。', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 260,
                      child: DoodleButton(label: '部屋を作る', icon: Icons.add_rounded, primary: true, seed: 61, onPressed: model.busy ? null : () => model.createRoom(g)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DoodleHeading('コードで参加', size: 21),
                    const SizedBox(height: 8),
                    const Text('相手の画面に出ている英字4文字', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 190,
                          child: TextField(
                            controller: _code,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 34, letterSpacing: 8),
                            inputFormatters: [_CodeFormatter()],
                            decoration: const InputDecoration(
                              hintText: 'ABCD',
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Palette.ink, width: 2.4)),
                              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Palette.ink, width: 3)),
                            ),
                            onSubmitted: (v) => model.join(v),
                          ),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(width: 120, child: DoodleButton(label: '参加', seed: 62, onPressed: model.busy ? null : () => model.join(_code.text))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
          const SizedBox(height: 22),
          const NearbyRooms(),
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
