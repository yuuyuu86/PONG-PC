import 'dart:convert';
import 'dart:typed_data';

import '../avatar/avatar.dart';
import '../games/core/catalog.dart';

/// PC 同士でやりとりするメッセージ。TCP の上に「4バイトの長さ + JSON」で載せる。
/// 種類は 't' で表す:
///   join {code, name, avatar, token?} / joined {side, token, game, resumed} / refused {reason: not_found|full|expired}
///   room {RoomInfo} / state {MatchState} / keys {KeyState} / ready {value} / rematch / leave / closed
///   invite {from, avatar, game, code, y, delay} / inviteAccept {name, avatar} / inviteDecline / ping / pong
typedef Msg = Map<String, Object?>;

enum RoomPhase { lobby, match, result }

class PlayerInfo {
  const PlayerInfo({required this.present, this.name = '', this.avatar = '', this.connected = false, this.ready = false, this.rematch = false});

  static const empty = PlayerInfo(present: false);

  final bool present;
  final String name;
  final String avatar;
  final bool connected;
  final bool ready;
  final bool rematch;

  Avatar get look => Avatar.decode(avatar);

  Msg toJson() => {'p': present, 'n': name, 'a': avatar, 'c': connected, 'r': ready, 'rm': rematch};

  static PlayerInfo fromJson(Msg m) => PlayerInfo(
        present: m['p'] == true,
        name: m['n'] as String? ?? '',
        avatar: m['a'] as String? ?? '',
        connected: m['c'] == true,
        ready: m['r'] == true,
        rematch: m['rm'] == true,
      );
}

/// 部屋の状態（待機画面・結果画面の表示に使う）
class RoomInfo {
  const RoomInfo({required this.code, required this.game, required this.phase, required this.you, required this.players, this.notice, this.rule});

  static const graceSeconds = 60;

  final String code;
  final GameKind game;
  final RoomPhase phase;
  final int you;
  final List<PlayerInfo> players;

  /// opponent_left / opponent_timeout
  final String? notice;

  /// 部屋を作った人が選んだルール（GameKind.ruleChoices の値）。古い版から届いたときは null
  final int? rule;
  int get ruleValue => rule ?? game.defaultRule;

  PlayerInfo get me => players[you];
  PlayerInfo get opponent => players[1 - you];

  Msg toJson() => {
        'code': code,
        'game': game.name,
        'phase': phase.name,
        'you': you,
        'players': [for (final p in players) p.toJson()],
        'notice': notice,
        'rule': rule,
      };

  static RoomInfo fromJson(Msg m) => RoomInfo(
        code: m['code'] as String,
        game: GameKind.values.byName(m['game'] as String),
        phase: RoomPhase.values.byName(m['phase'] as String),
        you: (m['you'] as num).toInt(),
        players: [for (final p in m['players'] as List) PlayerInfo.fromJson((p as Map).cast<String, Object?>())],
        notice: m['notice'] as String?,
        rule: (m['rule'] as num?)?.toInt(),
      );
}

abstract final class RoomCode {
  // 読み間違えにくい文字だけで4文字のコードを作る（I/O/B/S などを除外）
  static const chars = 'ACDEFGHJKLMNPQRTUVWXY';

  static String make(int Function(int max) nextInt) => String.fromCharCodes(List.generate(4, (_) => chars.codeUnitAt(nextInt(chars.length))));

  static String normalize(String raw) => raw.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');

  static bool isValid(String code) => RegExp(r'^[A-Z]{4}$').hasMatch(code);
}

abstract final class WireCodec {
  static const maxFrame = 1 << 20;

  static Uint8List encode(Msg m) {
    final body = utf8.encode(jsonEncode(m));
    final out = Uint8List(4 + body.length);
    ByteData.sublistView(out).setUint32(0, body.length);
    out.setRange(4, out.length, body);
    return out;
  }
}

/// 届いたバイト列からメッセージを取り出す。TCP は区切りを守らないので、分割・結合に関係なく組み立て直す。
class WireDecoder {
  final _buf = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// 取り出せたメッセージ。壊れたデータなら null。
  List<Msg>? add(List<int> chunk) {
    _buf.add(_pending);
    _buf.add(chunk);
    var data = _buf.takeBytes();
    final out = <Msg>[];
    var off = 0;
    while (data.length - off >= 4) {
      final len = ByteData.sublistView(data, off, off + 4).getUint32(0);
      if (len > WireCodec.maxFrame) return null;
      if (data.length - off - 4 < len) break;
      try {
        final m = jsonDecode(utf8.decode(Uint8List.sublistView(data, off + 4, off + 4 + len)));
        if (m is! Map) return null;
        out.add(m.cast<String, Object?>());
      } catch (_) {
        return null;
      }
      off += 4 + len;
    }
    _pending = Uint8List.fromList(Uint8List.sublistView(data, off));
    return out;
  }
}
