import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../app/records.dart';
import '../app/services.dart';
import '../avatar/avatar.dart';
import '../avatar/avatar_editor.dart';
import '../games/core/catalog.dart';
import '../ui/doodle.dart';
import '../ui/widgets.dart';
import 'root.dart';

/// 対戦結果の記録: 競技ごとの勝ち負けと、最近の試合
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return DoodleScaffold(
      title: 'せいせき',
      onBack: () => s.model.go(Screen.home),
      child: ListenableBuilder(
        listenable: s.settings,
        builder: (context, _) {
          final records = s.settings.records;
          if (records.isEmpty) {
            return const PageBody(maxWidth: 760, children: [
              SizedBox(height: 40),
              Text('まだ記録がありません。\n試合が終わると、ここに勝ち負けが残ります。', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, height: 1.6)),
            ]);
          }
          return PageBody(
            maxWidth: 860,
            children: [
              _Summary(records: records),
              const SizedBox(height: 26),
              const DoodleHeading('最近の試合', size: 21),
              const SizedBox(height: 10),
              for (final r in records.take(50)) _RecordRow(record: r),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 220,
                  child: DoodleButton(
                    label: '記録を消す',
                    icon: Icons.delete_outline_rounded,
                    fontSize: 17,
                    seed: 230,
                    onPressed: () async {
                      if (await confirmDialog(context, message: '対戦の記録をすべて消しますか？', ok: '消す')) s.settings.clearRecords();
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.records});
  final List<MatchRecord> records;

  @override
  Widget build(BuildContext context) {
    (int, int, int) count(Iterable<MatchRecord> rs) => (rs.where((r) => r.won == true).length, rs.where((r) => r.won == false).length, rs.where((r) => r.won == null).length);
    String text((int, int, int) c) => '${c.$1}勝 ${c.$2}敗${c.$3 > 0 ? ' ${c.$3}分' : ''}';
    final all = count(records);
    final played = all.$1 + all.$2;
    return DoodleBox(
      seed: 231,
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(text(all), style: const TextStyle(fontSize: 40, height: 1.1)),
              const SizedBox(width: 16),
              if (played > 0) Text('勝率 ${(all.$1 * 100 / played).round()}%', style: const TextStyle(fontSize: 20, color: Palette.pencil)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 26,
            runSpacing: 6,
            children: [
              for (final g in GameKind.values)
                Text('${g.title}  ${text(count(records.where((r) => r.game == g)))}', style: const TextStyle(fontSize: 18)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});
  final MatchRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final at = r.at;
    final date = '${at.month}/${at.day} ${at.hour}:${at.minute.toString().padLeft(2, '0')}';
    final mark = switch (r.won) {
      true => '勝ち',
      false => '負け',
      null => '引き分け',
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.faint))),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: r.won == true ? Palette.ink : null, border: Border.all(color: Palette.ink, width: 2), borderRadius: BorderRadius.circular(16)),
              child: Text(mark, style: TextStyle(fontSize: 17, color: r.won == true ? Palette.paper : Palette.ink)),
            ),
          ),
          const SizedBox(width: 14),
          Text('${r.myScore} - ${r.opponentScore}', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 18),
          AvatarIcon(avatar: Avatar.decode(r.opponentAvatar), size: 36),
          const SizedBox(width: 8),
          Expanded(child: Text('${r.opponent} と  ${r.game.title}（${r.game.ruleLabel(r.rule)}）', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18))),
          Text(date, style: const TextStyle(fontSize: 15, color: Palette.pencil)),
        ],
      ),
    );
  }
}
