import 'dart:math' as math;

/// 着せ替えできるパーツの種類。
enum AvatarPart {
  head('あたま', ['まる', 'たまご', 'しかく', 'おにぎり']),
  face('かお', ['にこにこ', 'キリッ', 'びっくり', 'ねむい', 'ウインク']),
  top('かみ・ぼうし', ['なし', 'ツンツン', 'キャップ', 'ハチマキ', 'リボン', 'アフロ']),
  pose('ポーズ', ['かまえ', 'バンザイ', 'ピース']);

  const AvatarPart(this.label, this.options);
  final String label;
  final List<String> options;
}

/// 試合結果などで一時的にとらせるポーズ。
enum AvatarMood { normal, win, lose }

/// 落書き風の棒人間プレイヤー。
/// 通信では "0.1.2.0" のような短い文字列でやり取りする。
class Avatar {
  Avatar(Map<AvatarPart, int> choices)
      : _choices = {
          for (final p in AvatarPart.values) p: (choices[p] ?? 0).clamp(0, p.options.length - 1),
        };

  final Map<AvatarPart, int> _choices;

  static final standard = Avatar(const {AvatarPart.top: 1});

  int operator [](AvatarPart part) => _choices[part]!;

  Avatar withChoice(AvatarPart part, int index) {
    final n = part.options.length;
    return Avatar({..._choices, part: ((index % n) + n) % n});
  }

  String optionLabel(AvatarPart part) => part.options[this[part]];

  String encode() => AvatarPart.values.map((p) => this[p]).join('.');

  /// 知らない形式や範囲外の値は、読めるところだけ使い残りは既定値にする(古い/新しいアプリとの互換)。
  static Avatar decode(String? raw) {
    if (raw == null || raw.isEmpty) return standard;
    final parts = raw.split('.');
    return Avatar({
      for (final (i, p) in AvatarPart.values.indexed)
        if (i < parts.length) p: int.tryParse(parts[i]) ?? 0,
    });
  }

  static Avatar random([math.Random? rnd]) {
    final r = rnd ?? math.Random();
    return Avatar({for (final p in AvatarPart.values) p: r.nextInt(p.options.length)});
  }

  /// 線の揺れを毎回同じにするための種
  int get seed => encode().hashCode & 0x7fffffff;

  @override
  bool operator ==(Object other) => other is Avatar && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
