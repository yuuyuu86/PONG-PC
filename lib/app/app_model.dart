import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../games/core/catalog.dart';
import '../games/core/match.dart';
import '../games/core/painting.dart';
import '../games/rally/rally.dart';
import '../net/discovery.dart';
import '../net/link.dart';
import '../net/peer_identity.dart';
import '../net/sessions.dart';
import '../net/wire.dart';
import 'feedback.dart';
import 'records.dart';
import 'updates.dart';
import 'version.dart';
import 'keyboard.dart';
import 'settings.dart';

/// 試合の表示用データ。キャンバスは毎フレーム latest を直接読むので、画面の作り直しは HUD が変わったときだけにする。
class MatchFeed extends ChangeNotifier {
  MatchState? latest;
  List<Burst> bursts = [];
  Hud hud = const Hud();

  void reset() {
    latest = null;
    bursts = [];
    hud = const Hud();
    notifyListeners();
  }

  void push(MatchState s, double now) {
    latest = s;
    for (final e in s.events) {
      if (e.x != null && e.y != null) {
        bursts.add(Burst(e.x!, e.y!, now, big: const {'spike', 'smash', 'counter', 'touche'}.contains(e.type)));
      }
    }
    bursts.removeWhere((b) => now - b.born > Burst.life);
    final h = Hud.of(s);
    if (h != hud) {
      hud = h;
      notifyListeners();
    }
  }
}

/// HUD とオーバーレイに出す情報（変わったときだけ画面を作り直す）
@immutable
class Hud {
  const Hud({
    this.phase = MatchPhase.intro,
    this.count = 0,
    this.score = const [0, 0],
    this.server,
    this.paused = false,
    this.resumeCount = 0,
    this.lastPoint,
    this.winner,
    this.endReason,
    this.extra,
    this.serving = false,
  });

  factory Hud.of(MatchState s) {
    final w = s.world;
    return Hud(
      phase: s.phase,
      count: s.timer.ceil(),
      score: List.of(s.score),
      server: s.server,
      paused: s.paused,
      resumeCount: s.resumeTimer.ceil(),
      lastPoint: s.lastPoint,
      winner: s.winner,
      endReason: s.endReason,
      extra: s.game.painter.hud(s.world),
      serving: w is RallyWorld && w.serving,
    );
  }

  final MatchPhase phase;
  final int count;
  final List<int> score;
  final int? server;
  final bool paused;
  final int resumeCount;
  final LastPoint? lastPoint;
  final int? winner;
  final String? endReason;
  final HudExtra? extra;
  final bool serving;

  @override
  bool operator ==(Object other) =>
      other is Hud &&
      other.phase == phase &&
      other.count == count &&
      other.score[0] == score[0] &&
      other.score[1] == score[1] &&
      other.server == server &&
      other.paused == paused &&
      other.resumeCount == resumeCount &&
      other.lastPoint?.n == lastPoint?.n &&
      other.winner == winner &&
      other.endReason == endReason &&
      other.extra == extra &&
      other.serving == serving;

  @override
  int get hashCode => Object.hash(phase, count, score[0], score[1], server, paused, resumeCount, lastPoint?.n, winner, extra, serving);
}

class ConnectionProblem {
  const ConnectionProblem({required this.title, required this.body, required this.isFinal, this.since});
  final String title;
  final String body;
  final bool isFinal;
  final DateTime? since;
}

enum Screen { home, create, join, nearby, records, room, match, result, howto, settings, profile }

/// 画面の流れとセッションをまとめる。タイトル → 対戦準備 → 部屋（待機）→ 試合 → 結果。
class AppModel extends ChangeNotifier implements SessionListener {
  AppModel({required this.settings, required this.feedback, Discovery? discovery, UpdateChecker? updates})
      : discovery = discovery ?? Discovery(),
        updates = updates ?? UpdateChecker() {
    keyboard = GameKeyboard((k) {
      host?.setKeys(k);
      guest?.setKeys(k);
    }, bindings: () => settings.keys);
  }

  final AppSettings settings;
  final GameFeedback feedback;
  final Discovery discovery;
  final UpdateChecker updates;

  /// 同じWi-Fiで、自分より新しい版を使っているPCの版（いちばん新しいもの）
  String? get newerNearby {
    String? best;
    for (final p in discovery.peers) {
      final v = p.version;
      if (v != null && AppVersion.compare(v, best ?? AppVersion.app) > 0) best = v;
    }
    return best;
  }
  final feed = MatchFeed();
  late final GameKeyboard keyboard;

  Screen screen = Screen.home;
  GameKind setupGame = GameKind.volley;
  RoomInfo? room;
  ({String text, bool error})? joinMessage;
  bool busy = false;
  ConnectionProblem? connection;
  DateTime? oppGoneAt;
  String? listenError;

  HostSession? host;
  GuestSession? guest;
  SecureServerSocket? _server;
  PeerIdentity? _identity;
  int? _lastIntroCount;

  /// この試合の結果をもう記録したか（試合が始まるたびに戻す）
  bool _recorded = false;

  Profile get profile => Profile(settings.playerName, settings.avatar.encode());
  bool get inRoom => host != null || guest != null;
  int get you => room?.you ?? 0;

  Future<void> start() async {
    try {
      // 相手からの接続（参加・再接続）を待ち受ける。ポートは空いているものを自動で使う
      final identity = await PeerIdentity.create();
      _identity = identity;
      final s = await SecureServerSocket.bind(InternetAddress.anyIPv4, 0, identity.context);
      s.listen(_incoming, onError: (_) {});
      _server = s;
    } catch (e) {
      listenError = '$e';
    }
    final identity = _identity;
    if (identity != null) {
      await discovery.start(name: profile.name, avatar: profile.avatar, tcpPort: _server?.port ?? 0, fingerprint: identity.fingerprint);
    }
    settings.addListener(_profileChanged);
    notifyListeners();
  }

  void _profileChanged() {
    host?.rename(profile);
    _advertise();
  }

  // 画面 ------------------------------------------------------------------

  void go(Screen s, {GameKind? game}) {
    screen = s;
    if (game != null) setupGame = game;
    keyboard.active = s == Screen.match && connection == null;
    notifyListeners();
  }

  void _route() {
    final r = room;
    if (r == null) return;
    switch (r.phase) {
      case RoomPhase.lobby:
        if (screen != Screen.room) go(Screen.room);
      case RoomPhase.match:
        if (screen != Screen.match) {
          feed.reset();
          _lastIntroCount = null;
          _recorded = false;
          go(Screen.match);
        }
      case RoomPhase.result:
        if (screen != Screen.result) go(Screen.result);
    }
  }

  // 部屋を作る・参加する ----------------------------------------------------

  void createRoom(GameKind game, {int? rule}) {
    _leaveQuietly();
    joinMessage = null;
    final h = HostSession(game: game, me: profile, listener: this, rule: rule)..onAdvertChange = _advertise;
    host = h;
    _advertise();
    h.broadcastRoom();
  }

  /// 部屋コードで参加。同じWi-Fiからその部屋を探してつなぐ。
  void join(String raw) {
    final code = RoomCode.normalize(raw);
    if (!RoomCode.isValid(code)) {
      joinMessage = (text: '部屋コードは英字4文字です。相手の画面に出ているコードを入力してください。', error: true);
      notifyListeners();
      return;
    }
    busy = true;
    joinMessage = (text: '部屋 $code を探しています…', error: false);
    notifyListeners();
    _findRoom(code, 12);
  }

  void _findRoom(String code, int tries) {
    final peer = discovery.peerWithCode(code);
    if (peer != null) {
      if (!peer.compatible) {
        busy = false;
        joinMessage = (text: versionText(peer.versionLabel), error: true);
        notifyListeners();
        return;
      }
      if (peer.state == PeerState.full) {
        busy = false;
        joinMessage = (text: refusalText('full'), error: true);
        notifyListeners();
        return;
      }
      joinMessage = (text: '部屋 $code に参加しています…', error: false);
      _leaveQuietly();
      final g = GuestSession(code: code, me: profile, listener: this, findHost: _findHost);
      guest = g;
      _advertise();
      notifyListeners();
      g.connect(peer.address, peer.port, fingerprint: peer.fingerprint);
      return;
    }
    if (tries <= 0) {
      busy = false;
      joinMessage = (text: refusalText('not_found'), error: true);
      notifyListeners();
      return;
    }
    // 見つかるまで少し待つ（起動直後は一覧がまだそろっていない）
    Timer(const Duration(milliseconds: 250), () => _findRoom(code, tries - 1));
  }

  (InternetAddress, int, String)? _findHost(String code) {
    final p = discovery.peerWithCode(code);
    return p == null ? null : (p.address, p.port, p.fingerprint);
  }

  /// 相手と通信の版が違うとき
  static String versionText(String theirs) =>
      '相手の PONG! と版が違うため、いっしょに遊べません（相手 $theirs / あなた ${AppVersion.app}）。2台とも新しい版にそろえてください。';

  static String refusalText(String reason) => switch (reason) {
        'version' => versionText('ちがう版'),
        'full' => 'この部屋にはすでに2人そろっています。別の部屋を作るか、相手にコードを確認してください。',
        'not_found' => '同じWi-Fiにその部屋が見つかりません。コードが合っているか、2台が同じWi-Fiにつながっているか確認してください。',
        'expired' => '部屋がなくなっていました。もう一度、部屋を作るかコードで参加してください。',
        'unreachable' => '相手のPCにつながりませんでした。2台が同じWi-Fiにつながっているか、ファイアウォールで PONG! が許可されているか確認してください。',
        _ => 'うまくいきませんでした。もう一度お試しください。',
      };

  // 部屋での操作 ----------------------------------------------------------

  void setReady(bool v) {
    host?.setReady(v);
    guest?.setReady(v);
  }

  /// 左右を入れ替える（待機中だけ）
  void swapSides() {
    host?.swapSides();
    guest?.swapSides();
  }

  void rematch() {
    host?.rematch();
    guest?.rematch();
  }

  /// 部屋を出てタイトルへ
  void leaveRoom() {
    _leaveQuietly();
    connection = null;
    go(Screen.home);
  }

  void _leaveQuietly() {
    host?.leave();
    guest?.leave();
    host = null;
    guest = null;
    room = null;
    oppGoneAt = null;
    toast = null;
    feed.reset();
    _advertise();
  }

  // 届いた接続の振り分け --------------------------------------------------

  void _incoming(SecureSocket socket) {
    final link = Link(socket);
    final timeout = Timer(const Duration(seconds: 10), () {
      if (link.onMessage != null) link.close();
    });
    link.onMessage = (m) {
      timeout.cancel();
      link.onMessage = null;
      switch (m['t']) {
        case 'join':
          final h = host;
          if (h != null) {
            h.handleJoin(link, m);
          } else {
            link
              ..send({'t': 'refused', 'reason': m['token'] == null ? 'not_found' : 'expired'})
              ..closeSoon();
          }
        default:
          link.close();
      }
    };
  }

  void _advertise() {
    final h = host;
    final p = profile;
    if (h != null) {
      discovery.advertise(
          name: p.name, avatar: p.avatar, state: h.phase == RoomPhase.lobby && !h.isFull ? PeerState.host : PeerState.full, code: h.code, game: h.game);
    } else {
      discovery.advertise(name: p.name, avatar: p.avatar, state: guest != null ? PeerState.busy : PeerState.idle);
    }
  }

  void _record(MatchState s) {
    final r = room;
    if (r == null) return;
    _recorded = true;
    final me = r.you;
    settings.addRecord(MatchRecord(
      at: DateTime.now(),
      game: r.game,
      rule: r.ruleValue,
      opponent: r.opponent.name,
      opponentAvatar: r.opponent.avatar,
      myScore: s.score[me],
      opponentScore: s.score[1 - me],
      won: s.winner == null ? null : s.winner == me,
    ));
  }

  // SessionListener -------------------------------------------------------

  /// 2人プレイで相手や部屋に起きたことの短いお知らせ（画面の上に数秒出す）
  ({String text, bool bad, int n})? toast;
  int _toastN = 0;

  void _toast(String text, {bool bad = false}) {
    final n = ++_toastN;
    toast = (text: text, bad: bad, n: n);
    Timer(const Duration(milliseconds: 3800), () {
      if (toast?.n != n) return;
      toast = null;
      notifyListeners();
    });
  }

  /// 前の部屋の状態と比べて、相手の参加・退出・準備・通信、左右の入れかえを知らせる
  void _announce(RoomInfo? prev, RoomInfo info) {
    if (prev == null || prev.code != info.code) return;
    final opp = info.opponent;
    // 相手は左右を入れかえても prev.opponent で比べられる
    final before = prev.opponent;
    final name = opp.name.isEmpty ? '相手' : opp.name;
    final match = info.phase == RoomPhase.match;
    if (!before.present && opp.present) {
      _toast('$name が部屋に入りました');
    } else if (before.present && !opp.present) {
      // 相手が抜けると左右も最初に戻るが、知らせるのは「抜けた」こと
      _toast('${before.name.isEmpty ? '相手' : before.name} が部屋から出ました。新しい相手を待っています', bad: true);
      feedback.play(Sound.lose, gain: 0.5);
    } else if (prev.you != info.you) {
      _toast('左右を入れかえました。あなたは${info.you == 0 ? '左' : '右'}の選手です。2台の置き方も入れかえてください');
    } else if (opp.present) {
      // 試合中の通信の切れ・戻りは、試合画面の案内で知らせるので重ねない
      if (before.connected && !opp.connected && !match) {
        _toast('$name の通信が切れました。つなぎ直すのを待っています', bad: true);
      } else if (!before.connected && opp.connected && !match) {
        _toast('$name がもどってきました');
      } else if (info.phase == RoomPhase.lobby && prev.phase == RoomPhase.lobby && before.ready != opp.ready) {
        _toast(opp.ready ? '$name が準備OKを押しました' : '$name が準備OKを取り消しました');
      } else if (info.phase == RoomPhase.result && !before.rematch && opp.rematch) {
        _toast('$name がもう一度やりたがっています');
      }
    }
  }

  @override
  void sessionRoom(RoomInfo info) {
    final prev = room;
    room = info;
    _announce(prev, info);
    final opp = info.opponent;
    if (opp.present && !opp.connected) {
      oppGoneAt ??= DateTime.now();
    } else {
      oppGoneAt = null;
    }
    if (opp.present && opp.connected && prev?.opponent.present != true) {
      feedback.play(Sound.point, gain: 0.5);
      }
    _route();
    notifyListeners();
  }

  @override
  void sessionState(MatchState s) {
    if (s.phase == MatchPhase.over && !_recorded) _record(s);
    feed.push(s, DateTime.now().millisecondsSinceEpoch / 1000);
    for (final e in s.events) {
      feedback.playEvent(e.type, side: e.side, you: you);
    }
    if (s.phase == MatchPhase.intro) {
      final c = s.timer.ceil();
      if (c != _lastIntroCount && c <= 3) feedback.play(Sound.tap, gain: 0.6);
      _lastIntroCount = c;
    }
  }

  @override
  void sessionJoined({required bool resumed}) {
    busy = false;
    joinMessage = null;
    connection = null;
    keyboard.active = screen == Screen.match;
    _advertise();
    notifyListeners();
  }

  @override
  void sessionJoinFailed(String reason) {
    busy = false;
    guest = null;
    joinMessage = (text: refusalText(reason), error: true);
    _advertise();
    notifyListeners();
  }

  @override
  void sessionReconnecting(DateTime since) {
    connection = ConnectionProblem(
      title: '接続が切れました',
      body: '自動でつなぎ直しています。試合は一時停止中で、つながれば同じところから再開します。Wi-Fi と相手のPCのようすを確認してください。',
      isFinal: false,
      since: since,
    );
    keyboard.active = false;
    notifyListeners();
  }

  @override
  void sessionEnded(String reason) {
    guest = null;
    room = null;
    final (title, body) = switch (reason) {
      'closed' => ('部屋が閉じられました', '部屋を作った人が退出しました。タイトルからもう一度遊べます。'),
      'gaveUp' => ('再接続できませんでした', '60秒たっても相手のPCにつながりませんでした。2台が同じWi-Fiにつながっているか、相手のアプリが開いているか確認して、もう一度部屋を作ってください。'),
      _ => ('部屋に戻れませんでした', '再接続の待ち時間を過ぎたか、相手が部屋を閉じたため、部屋がなくなりました。'),
    };
    connection = ConnectionProblem(title: title, body: body, isFinal: true);
    keyboard.active = false;
    _advertise();
    notifyListeners();
  }

  @override
  void dispose() {
    _leaveQuietly();
    _server?.close();
    keyboard.dispose();
    discovery.dispose();
    super.dispose();
  }
}
