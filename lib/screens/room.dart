import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_model.dart';
import '../app/services.dart';
import '../avatar/avatar.dart';
import '../avatar/avatar_editor.dart';
import '../avatar/avatar_painter.dart';
import '../net/discovery.dart';
import '../net/wire.dart';
import '../ui/doodle.dart';
import '../ui/widgets.dart';
import 'root.dart';

/// 部屋（作成・待機）。部屋を作った人はコードを見せるか、紙飛行機で招待する。
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
      'opponent_left' => '相手が退出しました。新しい相手はこのコードか招待で参加できます。',
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
            final showInvite = r.you == 0 && !opp.present;
            if (!showInvite) return left;
            if (constraints.maxWidth < 800 || MediaQuery.textScalerOf(context).scale(1) > 1.3) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 24), SideBySideHint(you: r.you), const SizedBox(height: 24), const InvitePanel()]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), const SizedBox(width: 26), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SideBySideHint(you: r.you), const SizedBox(height: 22), const InvitePanel()]))]);
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
    final role = side == 0 ? 'P1 左（部屋を作った人）' : 'P2 右（参加した人）';
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

/// 紙飛行機で招待: 同じWi-Fiで部屋に入っていないPCの一覧
class InvitePanel extends StatelessWidget {
  const InvitePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return DoodleBox(
      seed: 95,
      shadow: true,
      child: ListenableBuilder(
        listenable: model.discovery,
        builder: (context, _) {
          final peers = model.invitablePeers;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Icon(Icons.send_rounded, color: Palette.ink), SizedBox(width: 8), DoodleHeading('紙飛行機で招待', size: 22)]),
              const SizedBox(height: 10),
              const Text('近くのPCを選ぶと、紙飛行機が画面の右から飛び出して、相手の画面に招待状を届けます。', style: TextStyle(fontSize: 16, height: 1.45)),
              const SizedBox(height: 12),
              if (peers.isEmpty)
                const Row(children: [DoodleSpinner(size: 20), SizedBox(width: 10), Flexible(child: Text('同じWi-Fiで PONG! を開いているPCを探しています…', style: TextStyle(fontSize: 16)))])
              else
                for (final p in peers) _PeerRow(peer: p),
              if (model.inviteStatus != null) ...[
                const SizedBox(height: 8),
                Text(model.inviteStatus!, style: const TextStyle(fontSize: 16, color: Palette.pencil)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.peer});
  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: PlayerTag(avatar: Avatar.decode(peer.avatar), name: peer.name, iconSize: 40)),
          Builder(
            builder: (btnContext) => SizedBox(
              width: 190,
              child: DoodleButton(
                label: '招待を送る',
                icon: Icons.send_rounded,
                primary: true,
                fontSize: 18,
                seed: 96,
                onPressed: () {
                  // 紙飛行機はボタンの位置から飛び立つ
                  final box = btnContext.findRenderObject() as RenderBox?;
                  final from = box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
                  model.sendInvite(peer, from: from, window: MediaQuery.sizeOf(context));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 届いた招待状（紙飛行機が開いたもの）
class InviteLetter extends StatelessWidget {
  const InviteLetter({super.key, required this.invite});
  final IncomingInvite invite;

  @override
  Widget build(BuildContext context) {
    final model = Services.of(context).model;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.18),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          builder: (context, k, child) => Opacity(
            opacity: k.clamp(0, 1),
            child: Transform.rotate(angle: -0.02 - (1 - k) * 0.12, child: Transform.scale(scale: 0.4 + 0.6 * k, child: child)),
          ),
          child: SizedBox(
            width: 540,
            child: CustomPaint(
              painter: _LetterPainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 22, 34, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text('しょうたいじょう', style: TextStyle(fontSize: 18, color: Palette.pencil)),
                        const Spacer(),
                        // 切手
                        DoodleBox(seed: 161, dashed: true, padding: const EdgeInsets.all(8), child: AvatarView(avatar: Avatar.decode(invite.avatar), size: 44, bust: true)),
                      ],
                    ),
                    Text('${invite.from} さんから', style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 6),
                    Text('「PONG! ${invite.game.title}」で あそぼう！', style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 4),
                    Text(invite.game.tagline, style: const TextStyle(fontSize: 17, color: Palette.pencil)),
                    Text('部屋コード ${invite.code}', style: const TextStyle(fontSize: 17)),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 160, child: DoodleButton(label: 'ことわる', seed: 163, onPressed: model.declineInvite)),
                        const SizedBox(width: 16),
                        SizedBox(width: 200, child: DoodleButton(label: '参加する', icon: Icons.waving_hand_rounded, primary: true, seed: 162, onPressed: model.acceptInvite)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 便せん: 手描きの枠と影、薄い罫線
class _LetterPainter extends SketchBorderPainter {
  _LetterPainter() : super(seed: 160);

  @override
  void paint(Canvas canvas, Size size) {
    super.paint(canvas, size);
    for (var y = 74.0; y < size.height - 30; y += 34) {
      canvas.drawPath(Sketch.line(Offset(26, y), Offset(size.width - 34, y), seed: y.toInt(), wobble: 0.6), Sketch.pen(1, color: Palette.faint));
    }
  }
}

/// 設定画面などで使う見た目の編集（スマホ版 AvatarEditor）
class ProfileEditor extends StatelessWidget {
  const ProfileEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Services.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => AvatarEditor(value: settings.avatar, onChanged: (a) => settings.avatar = a),
    );
  }
}
