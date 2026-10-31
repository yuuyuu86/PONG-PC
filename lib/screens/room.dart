import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../avatar/avatar_painter.dart';
import '../net/wire.dart';
import '../ui/doodle.dart';
import '../ui/widgets.dart';
import 'root.dart';

/// 部屋（作成・待機）。部屋を作った人はコードを見せて相手を待つ。
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  bool _copied = false;

  Future<void> _leave() async {
    final model = Services.of(context).model;
    final ok = await confirmDialog(context, message: '部屋から退出しますか？', ok: '退出する');
    if (ok) model.leaveRoom();
  }

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    final r = model.room;
    if (r == null) {
      return const DoodleScaffold(
        showBack: false,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [DoodleSpinner(size: 40), SizedBox(height: 14), Text('部屋を用意しています…')])),
      );
    }
    final me = r.me, opp = r.opponent;
    final notice = switch (r.notice) {
      'opponent_left' => '相手が退出しました。新しい相手はこのコードか近くの部屋から参加できます。',
      'opponent_timeout' => '相手が時間内につなぎ直せなかったため、退出扱いになりました。',
      _ => null,
    };
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.you == 0) ...[
          const Text('相手にこのコードを伝えてください', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          const SizedBox(height: 10),
          CodeDisplay(code: r.code),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 220,
              child: DoodleButton(
                label: _copied ? 'コピーしました' : 'コピー',
                icon: Icons.copy_rounded,
                fontSize: 18,
                seed: 84,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: r.code));
                  setState(() => _copied = true);
                  Future.delayed(const Duration(milliseconds: 1500), () {
                    if (mounted) setState(() => _copied = false);
                  });
                },
              ),
            ),
          ),
        ] else
          Text('部屋 ${r.code} に参加しました', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 18),
        PlayersBox(room: r),
        const SizedBox(height: 18),
        Center(
          child: SizedBox(
            width: 300,
            child: DoodleButton(
              label: me.ready ? '準備OK！（取り消す）' : '準備OK',
              icon: me.ready ? Icons.check_rounded : Icons.directions_run_rounded,
              primary: !me.ready,
              seed: 90,
              onPressed: opp.present && opp.connected ? () => model.setReady(!me.ready) : null,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!(opp.present && opp.connected) || (me.ready && !opp.ready)) ...[const DoodleSpinner(size: 20), const SizedBox(width: 10)],
            Flexible(child: Text(_status(r), style: const TextStyle(fontSize: 18))),
          ],
        ),
        const SizedBox(height: 16),
        DoodleBox(seed: 88, dashed: true, child: ControlsList(controls: r.game.controls, size: 15)),
      ],
    );
    return DoodleScaffold(
      title: 'PONG! ${r.game.title}（${r.game.ruleLabel(r.ruleValue)}）　${r.you == 0 ? '部屋を作った' : '部屋に参加'}',
      onBack: _leave,
      child: PageBody(
        maxWidth: 1080,
        children: [
          if (notice != null) ...[DoodleBox(seed: 86, dashed: true, child: StatusLine(state: StatusKind.bad, text: notice)), const SizedBox(height: 16)],
          LayoutBuilder(builder: (context, constraints) {
            // 2台の並べ方と左右の入れかえは、両方のPCに、相手がそろってからも出す
            final hint = SideBySideHint(you: r.you, onSwap: model.swapSides);
            if (constraints.maxWidth < 800 || MediaQuery.textScalerOf(context).scale(1) > 1.3) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 24), hint]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), const SizedBox(width: 26), Expanded(child: hint)]);
          }),
        ],
      ),
    );
  }

  String _status(RoomInfo r) {
    final me = r.me, opp = r.opponent;
    if (!opp.present) return r.you == 0 ? '相手の参加を待っています…' : '相手を待っています…';
    if (!opp.connected) return '相手の通信が切れています。つなぎ直すのを待っています…';
    if (!me.ready) return 'そろいました！「準備OK」を押してください';
    if (!opp.ready) return '相手の準備を待っています…';
    return 'まもなく開始！';
  }
}

/// 部屋コードを大きく（スマホ版 _CodeDisplay）
class CodeDisplay extends StatelessWidget {
  const CodeDisplay({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '部屋コード ${code.split('').join(' ')}',
      child: Center(
        child: DoodleBox(
          seed: 91,
          shadow: true,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 22),
          child: SelectableText(code, textAlign: TextAlign.center, style: const TextStyle(fontSize: 80, letterSpacing: 18, height: 1.15)),
        ),
      ),
    );
  }
}

/// 2人の参加状態と左右の割り当て（●接続中 / ○まだいない / ×切断）
class PlayersBox extends StatelessWidget {
  const PlayersBox({super.key, required this.room});
  final RoomInfo room;

  @override
  Widget build(BuildContext context) {
    return DoodleBox(
      seed: 86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DoodleHeading('プレイヤー', size: 20),
          const SizedBox(height: 10),
          for (var side = 0; side < 2; side++) ...[
            _row(side),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// 1人分: アバター、名前（あなた）、その下に役割と状態
  Widget _row(int side) {
    final p = room.players[side];
    final role = side == 0 ? 'P1 左' : 'P2 右';
    final status = !p.present
        ? 'まだいません'
        : !p.connected
            ? '通信が切れています'
            : p.ready
                ? '準備完了'
                : '待機中';
    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: p.present ? AvatarView(avatar: p.look, size: 48, bust: true) : const Center(child: DoodleSpinner(size: 22)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.present ? p.name + (side == room.you ? '（あなた）' : '') : '相手を待っています', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, height: 1.2)),
              Text(role, style: const TextStyle(fontSize: 15, color: Palette.pencil)),
            ],
          ),
        ),
        SizedBox(width: 170, child: StatusLine(state: !p.present ? StatusKind.waiting : !p.connected ? StatusKind.bad : StatusKind.ok, text: status)),
      ],
    );
  }
}
