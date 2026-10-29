import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../games/core/catalog.dart';
import '../games/core/common.dart';
import '../games/core/match.dart';
import 'link.dart';
import 'wire.dart';

/// セッションから画面側（AppModel）へのお知らせ
abstract class SessionListener {
  void sessionRoom(RoomInfo info);

  /// world は描画用（ホストは計算中のもの、ゲストは届いたもの）
  void sessionState(MatchState state);

  /// ゲスト: 部屋に入れた / 再接続できた
  void sessionJoined({required bool resumed});

  /// ゲスト: 参加できなかった（not_found / full / expired / unreachable）
  void sessionJoinFailed(String reason);

  /// ゲスト: 接続が切れて再接続中
  void sessionReconnecting(DateTime since);

  /// 部屋が終わった（closed: ホストが閉じた / gaveUp: 再接続できなかった / expired: 部屋がもうない）
  void sessionEnded(String reason);

  void inviteDeclined(String name);
}

/// 自分の名前と見た目
class Profile {
  const Profile(this.name, this.avatar);
  final String name;
  final String avatar;
}

// ---------------------------------------------------------------------------
// ホスト（部屋を作ったPC）。試合の権威ある状態はここだけで計算する。

class _Guest {
  _Guest(this.link, this.name, this.avatar, this.token);

  Link? link;
  final String name;
  final String avatar;
  final String token;
  bool connected = true;
  bool ready = false;
  bool rematch = false;
  KeyState keys = const KeyState();
}

class HostSession {
  HostSession({required this.game, required Profile me, required this.listener, math.Random? random})
      : _me = me,
        _random = random ?? math.Random() {
    code = RoomCode.make(_random.nextInt);
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      _guest?.link?.checkAlive(Duration(seconds: phase == RoomPhase.match ? 3 : 6));
    });
  }

  static const tick = 1 / 60;

  final GameKind game;
  final SessionListener listener;
  final math.Random _random;
  late final String code;
  Profile _me;
  RoomPhase phase = RoomPhase.lobby;
  _Guest? _guest;
  MatchEngine? engine;
  bool _myReady = false;
  bool _myRematch = false;
  String? _notice;
  KeyState _myKeys = const KeyState();
  final _myPress = PressTracker();
  final _guestPress = PressTracker();
  Timer? _grace;
  Timer? _loop;
  Timer? _heartbeat;
  final _clock = Stopwatch();
  double _acc = 0;
  final _invites = <Link>[];

  /// 部屋の状態が変わったとき（お知らせの内容を更新するため）
  void Function()? onAdvertChange;

  bool get isFull => _guest != null;
  bool get guestConnected => _guest?.connected ?? false;

  // 参加の受け付け --------------------------------------------------------

  /// 新しい接続の最初のメッセージが join だったとき
  void handleJoin(Link link, Msg m) {
    final token = m['token'] as String?;
    if (m['code'] != code) return _refuse(link, 'not_found');
    final g = _guest;
    if (token != null && g != null && g.token == token) {
      // 再接続: 同じ席に戻す
      g.link?.onClose = null;
      g.link?.close();
      g
        ..link = link
        ..connected = true
        ..keys = const KeyState();
      _grace?.cancel();
      _guestPress.reset();
      _attach(link);
      link.send({'t': 'joined', 'side': 1, 'token': g.token, 'game': game.name, 'resumed': true});
      if (phase == RoomPhase.match && engine?.state.paused == true) engine!.resume();
      broadcastRoom();
      final e = engine;
      if (e != null) link.send({'t': 'state', 's': e.state.toJson()});
      return;
    }
    if (token != null && g == null) return _refuse(link, 'expired');
    if (g != null) return _refuse(link, 'full');
    _admit(link, m['name'] as String? ?? 'あいて', m['avatar'] as String? ?? '');
  }

  void _refuse(Link link, String reason) {
    link.send({'t': 'refused', 'reason': reason});
    link.closeSoon();
  }

  void _admit(Link link, String name, String avatar) {
    final token = List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
    _guest = _Guest(link, name, avatar, token);
    _notice = null;
    _attach(link);
    link.send({'t': 'joined', 'side': 1, 'token': token, 'game': game.name, 'resumed': false});
    broadcastRoom();
    onAdvertChange?.call();
    for (final l in [..._invites]) {
      if (l != link) l.close();
    }
  }

  void _attach(Link link) {
    link.onMessage = (m) {
      if (_guest?.link == link) _handleGuest(m);
    };
    link.onClose = () {
      if (_guest?.link == link) _guestDropped();
    };
  }

  // 招待（紙飛行機） ------------------------------------------------------

  Future<void> sendInvite({required InternetAddress address, required int port, required String peerName, required double y, required double delay}) async {
    final link = await Link.connect(address, port);
    if (link == null) {
      listener.inviteDeclined(peerName);
      return;
    }
    _invites.add(link);
    link.onMessage = (m) {
      switch (m['t']) {
        case 'inviteAccept':
          _invites.remove(link);
          if (_guest == null) {
            _admit(link, m['name'] as String? ?? peerName, m['avatar'] as String? ?? '');
          } else {
            _refuse(link, 'full');
          }
        case 'inviteDecline':
          _invites.remove(link);
          listener.inviteDeclined(peerName);
          link.close();
      }
    };
    link.onClose = () => _invites.remove(link);
    link.send({'t': 'invite', 'from': _me.name, 'avatar': _me.avatar, 'game': game.name, 'code': code, 'y': y, 'delay': delay});
    // 返事がないまま長く待たない
    Timer(const Duration(seconds: 90), () {
      if (_invites.contains(link)) link.close();
    });
  }

  // 相手からのメッセージ --------------------------------------------------

  void _handleGuest(Msg m) {
    final g = _guest!;
    switch (m['t']) {
      case 'keys':
        final k = KeyState.fromJson((m['k'] as Map).cast<String, Object?>());
        _guestPress.baseline(k);
        g.keys = k;
      case 'ready':
        if (phase != RoomPhase.lobby) return;
        g.ready = m['value'] == true;
        _checkStart();
      case 'rematch':
        if (phase != RoomPhase.result) return;
        g.rematch = true;
        _checkRematch();
      case 'leave':
        _removeGuest('opponent_left');
    }
  }

  void _guestDropped() {
    final g = _guest;
    if (g == null) return;
    g
      ..connected = false
      ..link = null
      ..keys = const KeyState();
    if (phase == RoomPhase.match) engine?.pause();
    _grace?.cancel();
    _grace = Timer(const Duration(seconds: RoomInfo.graceSeconds), () => _removeGuest('opponent_timeout'));
    broadcastRoom();
  }

  /// 相手が退出した / 戻れなかった。自分は部屋に残り、新しい相手を待つかタイトルへ戻れる。
  void _removeGuest(String notice) {
    _grace?.cancel();
    final link = _guest?.link;
    _guest = null;
    link?.onClose = null;
    link?.close();
    _stopLoop();
    engine = null;
    phase = RoomPhase.lobby;
    _myReady = false;
    _myRematch = false;
    _notice = notice;
    broadcastRoom();
    onAdvertChange?.call();
  }

  // 自分の操作 ------------------------------------------------------------

  void setReady(bool v) {
    if (phase != RoomPhase.lobby) return;
    _myReady = v;
    _checkStart();
  }

  void rematch() {
    if (phase != RoomPhase.result) return;
    _myRematch = true;
    _checkRematch();
  }

  void setKeys(KeyState k) {
    _myPress.baseline(k);
    _myKeys = k;
  }

  void rename(Profile me) {
    _me = me;
    broadcastRoom();
  }

  void leave() {
    final link = _guest?.link;
    link?.onClose = null;
    link?.send(const {'t': 'closed'});
    link?.closeSoon();
    _grace?.cancel();
    for (final l in [..._invites]) {
      l.close();
    }
    _stopLoop();
    _heartbeat?.cancel();
    _guest = null;
  }

  void _checkStart() {
    final g = _guest;
    if (_myReady && g != null && g.connected && g.ready) {
      _startMatch();
    } else {
      broadcastRoom();
    }
  }

  void _checkRematch() {
    final g = _guest;
    if (_myRematch && g != null && g.connected && g.rematch) {
      _startMatch();
    } else {
      broadcastRoom();
    }
  }

  void _startMatch() {
    engine = MatchEngine(game, random: _random);
    phase = RoomPhase.match;
    _notice = null;
    _myReady = false;
    _myRematch = false;
    _guest!
      ..ready = false
      ..rematch = false;
    _myPress
      ..reset()
      ..baseline(_myKeys);
    _guestPress.reset();
    broadcastRoom();
    onAdvertChange?.call();
    _startLoop();
  }

  // 試合のループ（60Hz 固定ステップ） ---------------------------------------

  void _startLoop() {
    _stopLoop();
    _acc = 0;
    _clock
      ..reset()
      ..start();
    _loop = Timer.periodic(const Duration(milliseconds: 4), (_) => _frame());
  }

  void _stopLoop() {
    _loop?.cancel();
    _loop = null;
  }

  void _frame() {
    final dt = _clock.elapsedMicroseconds / 1e6;
    _clock
      ..reset()
      ..start();
    _acc = math.min(0.25, _acc + dt); // 長く止まった後に早送りしすぎない
    while (_acc >= tick) {
      _acc -= tick;
      _step();
      if (phase != RoomPhase.match) return;
    }
  }

  void _step() {
    final e = engine;
    if (e == null) return;
    final g = _guest;
    final inputs = [
      _myPress.input(_myKeys, connected: true),
      _guestPress.input(g?.keys ?? const KeyState(), connected: g?.connected ?? false),
    ];
    e.step(inputs, tick);
    final s = e.state;
    g?.link?.send({'t': 'state', 's': s.toJson()});
    listener.sessionState(s);
    if (s.phase == MatchPhase.over) {
      phase = RoomPhase.result;
      _stopLoop();
      broadcastRoom();
      onAdvertChange?.call();
    }
  }

  // 部屋の状態 ------------------------------------------------------------

  RoomInfo roomInfo(int side) {
    final g = _guest;
    return RoomInfo(
      code: code,
      game: game,
      phase: phase,
      you: side,
      players: [
        PlayerInfo(present: true, name: _me.name, avatar: _me.avatar, connected: true, ready: _myReady, rematch: _myRematch),
        g == null ? PlayerInfo.empty : PlayerInfo(present: true, name: g.name, avatar: g.avatar, connected: g.connected, ready: g.ready, rematch: g.rematch),
      ],
      notice: side == 0 ? _notice : null,
    );
  }

  void broadcastRoom() {
    listener.sessionRoom(roomInfo(0));
    final g = _guest;
    if (g != null && g.connected) g.link?.send({'t': 'room', 'r': roomInfo(1).toJson()});
  }
}

// ---------------------------------------------------------------------------
// ゲスト（参加したPC）。入力を送り、届いた状態を表示する。切れたら自動で再接続する。

typedef HostFinder = (InternetAddress, int)? Function(String code);

class GuestSession {
  GuestSession({required this.code, required Profile me, required this.listener, required this.findHost}) : _me = me {
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  final String code;
  final SessionListener listener;

  /// 再接続先を探す方法（通常は近くのPCの一覧から部屋コードで探す。テストでは差し替える）
  HostFinder findHost;
  final Profile _me;
  GameKind? game;
  String? _token;
  Link? _link;
  bool _connecting = false;
  KeyState _keys = const KeyState();
  bool _leaving = false;
  DateTime? _lostAt;
  bool _inMatch = false;
  Timer? _timer;
  int _ticks = 0;

  /// 部屋コードで参加
  Future<void> connect(InternetAddress host, int port) async {
    _connecting = true;
    final l = await Link.connect(host, port);
    _connecting = false;
    if (_leaving) {
      l?.close();
      return;
    }
    if (l == null) {
      _dropped();
      return;
    }
    _attach(l);
    l.send({'t': 'join', 'code': code, 'name': _me.name, 'avatar': _me.avatar, 'token': _token});
  }

  /// 招待を受けた接続をそのまま使って参加する
  void adopt(Link l) {
    _attach(l);
    l.send({'t': 'inviteAccept', 'name': _me.name, 'avatar': _me.avatar});
  }

  void _attach(Link l) {
    _link?.onClose = null;
    _link?.close();
    _link = l;
    l.onMessage = (m) {
      if (_link == l) _handle(m);
    };
    l.onClose = () {
      if (_link == l) _dropped();
    };
  }

  void _handle(Msg m) {
    switch (m['t']) {
      case 'joined':
        _token = m['token'] as String;
        game = GameKind.values.byName(m['game'] as String);
        _lostAt = null;
        listener.sessionJoined(resumed: m['resumed'] == true);
        _link?.send({'t': 'keys', 'k': _keys.toJson()});
      case 'refused':
        final first = _token == null;
        _end();
        if (first) {
          listener.sessionJoinFailed(m['reason'] as String? ?? '');
        } else {
          listener.sessionEnded('expired');
        }
      case 'room':
        final info = RoomInfo.fromJson((m['r'] as Map).cast<String, Object?>());
        _inMatch = info.phase == RoomPhase.match;
        listener.sessionRoom(info);
      case 'state':
        listener.sessionState(MatchState.fromJson((m['s'] as Map).cast<String, Object?>()));
      case 'closed':
        _end();
        listener.sessionEnded('closed');
    }
  }

  void _dropped() {
    _link = null;
    if (_leaving) return;
    if (_token == null) {
      _end();
      listener.sessionJoinFailed('unreachable');
      return;
    }
    if (_lostAt == null) {
      _lostAt = DateTime.now();
      listener.sessionReconnecting(_lostAt!);
    }
  }

  /// 0.25秒ごと: 入力の送り直し、生存確認、再接続の試行
  void _tick() {
    _ticks++;
    final l = _link;
    if (l != null) {
      if (_inMatch) l.send({'t': 'keys', 'k': _keys.toJson()});
      if (_ticks % 4 == 0) l.checkAlive(Duration(seconds: _inMatch ? 3 : 6));
      return;
    }
    final lost = _lostAt;
    if (lost == null || _leaving || _connecting) return;
    if (DateTime.now().difference(lost).inSeconds > RoomInfo.graceSeconds) {
      _end();
      listener.sessionEnded('gaveUp');
      return;
    }
    // 部屋コードを知らせているPCを探してつなぎ直す
    if (_ticks % 6 == 0) {
      final h = findHost(code);
      if (h != null) connect(h.$1, h.$2);
    }
  }

  void setKeys(KeyState k) {
    _keys = k;
    _link?.send({'t': 'keys', 'k': k.toJson()});
  }

  void setReady(bool v) => _link?.send({'t': 'ready', 'value': v});
  void rematch() => _link?.send(const {'t': 'rematch'});

  /// 通信が切れた状況を作る（テスト用）
  void simulateDrop() => _link?.close();

  void leave() {
    _link?.send(const {'t': 'leave'});
    _end();
  }

  void _end() {
    _leaving = true;
    _timer?.cancel();
    final l = _link;
    _link = null;
    if (l != null) {
      l
        ..onClose = null
        ..onMessage = null
        ..closeSoon();
    }
  }
}
