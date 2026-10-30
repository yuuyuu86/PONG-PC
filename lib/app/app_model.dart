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

/// 紙飛行機の飛行（自分の画面から出ていく / 相手の画面に入ってくる）
class Flight {
  Flight({required this.outbound, required this.from, required this.yFrac}) : start = DateTime.now();
  final bool outbound;
  final Offset from;
  final double yFrac;
  final DateTime start;
}

class IncomingInvite {
  IncomingInvite({required this.from, required this.avatar, required this.game, required this.code, required this.link});
  final String from;
  final String avatar;
  final GameKind game;
  final String code;
  final Link link;
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
  AppModel({required this.settings, required this.feedback, Discovery? discovery}) : discovery = discovery ?? Discovery() {
    keyboard = GameKeyboard((k) {
      host?.setKeys(k);
      guest?.setKeys(k);
    }, bindings: () => settings.keys);
  }

  final AppSettings settings;
  final GameFeedback feedback;
  final Discovery discovery;
  final feed = MatchFeed();
  late final GameKeyboard keyboard;

  Screen screen = Screen.home;
  GameKind setupGame = GameKind.volley;
  RoomInfo? room;
  ({String text, bool error})? joinMessage;
  bool busy = false;
  ConnectionProblem? connection;
  IncomingInvite? invite;
  final flights = <Flight>[];
  String? inviteStatus;
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
      // 相手からの接続（参加・招待・再接続）を待ち受ける。ポートは空いているものを自動で使う
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
    inviteStatus = null;
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

  static String refusalText(String reason) => switch (reason) {
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
    feed.reset();
    inviteStatus = null;
    _advertise();
  }

  // 招待（紙飛行機） ------------------------------------------------------

  /// 招待できる相手: 部屋に入っていない近くのPC
  List<Peer> get invitablePeers => discovery.peers.where((p) => p.state == PeerState.idle).toList();

  void sendInvite(Peer peer, {required Offset from, required Size window}) {
    final h = host;
    if (h == null) return;
    feedback.play(Sound.plane);
    const yFrac = 0.38;
    final flight = Flight(outbound: true, from: from, yFrac: yFrac);
    flights.add(flight);
    final delay = PlaneMotion.outCrossTime(from, window, yFrac);
    h.sendInvite(address: peer.address, port: peer.port, fingerprint: peer.fingerprint, peerName: peer.name, y: yFrac, delay: delay);
    inviteStatus = '${peer.name} に紙飛行機を飛ばしました。返事を待っています…';
    notifyListeners();
    Timer(Duration(milliseconds: ((PlaneMotion.outTotal + 0.8) * 1000).round()), () {
      flights.remove(flight);
      notifyListeners();
    });
  }

  void _receiveInvite(Msg m, Link link) {
    // 部屋に入っている・すでに招待状を見ているときはことわる
    final game = GameKind.values.asNameMap()[m['game']];
    if (inRoom || invite != null || game == null) {
      link.send(const {'t': 'inviteDecline'});
      link.closeSoon();
      return;
    }
    link.onClose = () {
      if (invite?.link == link) {
        invite = null;
        notifyListeners();
      }
    };
    final y = (m['y'] as num?)?.toDouble() ?? 0.4;
    final delay = ((m['delay'] as num?)?.toDouble() ?? 0).clamp(0, 3);
    Timer(Duration(milliseconds: (delay * 1000).round()), () {
      if (link.isClosed) return;
      feedback.play(Sound.plane, gain: 0.8);
      final flight = Flight(outbound: false, from: Offset.zero, yFrac: y);
      flights.add(flight);
      notifyListeners();
      Timer(Duration(milliseconds: (PlaneMotion.inLand * 1000).round()), () {
        if (link.isClosed) return;
        feedback.play(Sound.point, gain: 0.6);
        invite = IncomingInvite(from: m['from'] as String? ?? 'だれか', avatar: m['avatar'] as String? ?? '', game: game, code: m['code'] as String? ?? '', link: link);
        notifyListeners();
      });
      Timer(Duration(milliseconds: ((PlaneMotion.inTotal + 0.8) * 1000).round()), () {
        flights.remove(flight);
        notifyListeners();
      });
    });
  }

  void acceptInvite() {
    final inv = invite;
    if (inv == null) return;
    invite = null;
    _leaveQuietly();
    final g = GuestSession(code: inv.code, me: profile, listener: this, findHost: _findHost);
    guest = g;
    busy = true;
    _advertise();
    g.adopt(inv.link);
    notifyListeners();
  }

  void declineInvite() {
    final inv = invite;
    if (inv == null) return;
    invite = null;
    inv.link
      ..send(const {'t': 'inviteDecline'})
      ..closeSoon();
    notifyListeners();
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
        case 'invite':
          _receiveInvite(m, link);
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

  @override
  void sessionRoom(RoomInfo info) {
    final prev = room;
    room = info;
    final opp = info.opponent;
    if (opp.present && !opp.connected) {
      oppGoneAt ??= DateTime.now();
    } else {
      oppGoneAt = null;
    }
    if (opp.present && opp.connected && prev?.opponent.present != true) {
      feedback.play(Sound.point, gain: 0.5);
      inviteStatus = null;
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
  void inviteDeclined(String name) {
    inviteStatus = '$name は招待をことわりました（または届きませんでした）。';
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

/// 招待の紙飛行機の動き。2台のPCを並べたとき、左のPCの右端から飛び出して、
/// 右のPCの左端の同じ高さから入ってくるように見せる。
abstract final class PlaneMotion {
  static const pop = 0.26; // その場で紙を折って飛行機にする時間
  static const outTravel = 1.5;
  static const outTotal = pop + outTravel;
  static const inTravel = 1.7;
  static const inLand = inTravel + 0.12;
  static const inTotal = inTravel + 0.35;

  static Offset bezier(List<Offset> p, double t) {
    final u = 1 - t;
    final a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
    return p[0] * a + p[1] * b + p[2] * c + p[3] * d;
  }

  static List<Offset> outPath(Offset from, Size size, double yFrac) {
    final y = yFrac * size.height;
    return [from, Offset(from.dx + 40, from.dy - 230), Offset(size.width * 0.78, y - 150), Offset(size.width + 120, y)];
  }

  /// だんだん加速して飛び去る
  static double outEase(double t) => t * t * (1.6 - 0.6 * t);

  static List<Offset> inPath(Size size, double yFrac) {
    final y = yFrac * size.height;
    return [Offset(-120, y), Offset(size.width * 0.3, y - 30), Offset(size.width * 0.4, size.height * 0.26), Offset(size.width * 0.5, size.height * 0.42)];
  }

  /// 速く入ってきて、ふわっと減速する
  static double inEase(double t) => 1 - (1 - t) * (1 - t) * (1 - 0.4 * t);

  /// 自分の画面の右端を越えるまでの時間（相手の画面ではこの時間だけ待ってから入ってくる）
  static double outCrossTime(Offset from, Size size, double yFrac) {
    final path = outPath(from, size, yFrac);
    for (var i = 0; i <= 200; i++) {
      final t = i / 200;
      if (bezier(path, outEase(t)).dx >= size.width) return pop + t * outTravel;
    }
    return outTotal;
  }
}
