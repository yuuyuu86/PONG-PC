import 'dart:convert';

import '../games/core/catalog.dart';

/// 1試合の記録（このPCに保存する）
class MatchRecord {
  const MatchRecord({required this.at, required this.game, required this.rule, required this.opponent, required this.opponentAvatar, required this.myScore, required this.opponentScore, required this.won});

  final DateTime at;
  final GameKind game;
  final int rule;
  final String opponent;
  final String opponentAvatar;
  final int myScore;
  final int opponentScore;

  /// 引き分けは null
  final bool? won;

  Map<String, Object?> toJson() => {'at': at.millisecondsSinceEpoch, 'g': game.name, 'r': rule, 'o': opponent, 'oa': opponentAvatar, 'm': myScore, 'os': opponentScore, 'w': won};

  static MatchRecord? fromJson(Object? raw) {
    if (raw is! Map || raw['at'] is! num) return null;
    final game = GameKind.values.asNameMap()[raw['g']];
    if (game == null) return null;
    return MatchRecord(
      at: DateTime.fromMillisecondsSinceEpoch((raw['at'] as num).toInt()),
      game: game,
      rule: (raw['r'] as num?)?.toInt() ?? game.defaultRule,
      opponent: raw['o'] as String? ?? '',
      opponentAvatar: raw['oa'] as String? ?? '',
      myScore: (raw['m'] as num?)?.toInt() ?? 0,
      opponentScore: (raw['os'] as num?)?.toInt() ?? 0,
      won: raw['w'] as bool?,
    );
  }

  static List<MatchRecord> decodeList(String? raw) {
    if (raw == null) return [];
    // 壊れた記録が1件あっても、ほかの記録は読めるようにする
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final out = <MatchRecord>[];
      for (final e in list) {
        try {
          final r = MatchRecord.fromJson(e);
          if (r != null) out.add(r);
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<MatchRecord> list) => jsonEncode([for (final r in list) r.toJson()]);
}
