import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pong_pc/games/core/catalog.dart';
import 'package:pong_pc/games/core/common.dart';
import 'package:pong_pc/games/core/match.dart';
import 'package:pong_pc/games/fencing/fencing.dart';
import 'package:pong_pc/net/discovery.dart';
import 'package:pong_pc/net/link.dart';
import 'package:pong_pc/net/peer_identity.dart';
import 'package:pong_pc/net/sessions.dart';
import 'package:pong_pc/net/wire.dart';

class Recorder implements SessionListener {
  final rooms = <RoomInfo>[];
  final states = <MatchState>[];
  final stateJson = <int, String>{};
  var joined = 0, reconnecting = 0;
  final failures = <String>[], ended = <String>[], declined = <String>[];
  RoomInfo? get room => rooms.isEmpty ? null : rooms.last;

  @override
  void sessionRoom(RoomInfo info) => rooms.add(info);
  @override
  void sessionState(MatchState state) {
    states.add(state);
    stateJson[state.tick] = jsonEncode(state.toJson());
  }

  @override
  void sessionJoined({required bool resumed}) => joined++;
  @override
  void sessionJoinFailed(String reason) => failures.add(reason);
  @override
  void sessionReconnecting(DateTime since) => reconnecting++;
  @override
  void sessionEnded(String reason) => ended.add(reason);
  @override
  void inviteDeclined(String name) => declined.add(name);
}

Future<void> waitUntil(String label, bool Function() cond, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('待ちきれませんでした: $label');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late SecureServerSocket server;
  late HostSession host;
  late PeerIdentity identity;
  final lo = InternetAddress.loopbackIPv4;

  /// ループバックで待ち受け、届いた接続の最初のメッセージを振り分ける（アプリの AppModel と同じ）
  Future<void> listen() async {
    server = await SecureServerSocket.bind(lo, 0, identity.context);
    server.listen((s) {
      final link = Link(s);
      link.onMessage = (m) {
        link.onMessage = null;
        if (m['t'] == 'join') host.handleJoin(link, m);
      };
    }, onError: (_) {});
  }

  setUpAll(() async {
    identity = await PeerIdentity.create();
  });

  tearDown(() async {
    host.leave();
    await server.close();
  });

  test('部屋コードで参加 → 試合 → 状態が一致 → 切断で一時停止 → 自動再接続で再開 → 退出', () async {
    final hostRec = Recorder(), guestRec = Recorder();
    host = HostSession(game: GameKind.fencing, me: const Profile('ホスト', '0.0.1.0'), listener: hostRec);
    await listen();
    final port = server.port;

    // 間違ったコードでは入れない
    final wrong = GuestSession(code: 'ZZZZ', me: const Profile('まちがい', ''), listener: guestRec, findHost: (_) => null);
    await wrong.connect(lo, port, fingerprint: identity.fingerprint);
    await waitUntil('not_found', () => guestRec.failures.contains('not_found'));

    final guest = GuestSession(code: host.code, me: const Profile('ゲスト', '1.1.1.1'), listener: guestRec, findHost: (_) => (lo, port, identity.fingerprint));
    await guest.connect(lo, port, fingerprint: identity.fingerprint);
    await waitUntil('参加', () => guestRec.joined == 1 && hostRec.room?.players[1].present == true);
    expect(guestRec.room?.you, 1);
    expect(hostRec.room?.players[1].name, 'ゲスト');
    expect(guestRec.room?.players[0].avatar, '0.0.1.0', reason: 'アバターも相手に届く');

    // 3人目は満員
    final third = Recorder();
    await GuestSession(code: host.code, me: const Profile('3人目', ''), listener: third, findHost: (_) => null).connect(lo, port, fingerprint: identity.fingerprint);
    await waitUntil('full', () => third.failures.contains('full'));

    // 片方だけ準備OKでは始まらない
    host.setReady(true);
    await waitUntil('ホスト準備', () => guestRec.room?.players[0].ready == true);
    expect(hostRec.room?.phase, RoomPhase.lobby);
    guest.setReady(true);
    await waitUntil('試合開始', () => hostRec.room?.phase == RoomPhase.match && guestRec.room?.phase == RoomPhase.match);
    await waitUntil('プレー', () => guestRec.states.isNotEmpty && guestRec.states.last.phase == MatchPhase.play, timeout: const Duration(seconds: 8));

    // 両方のPCで同じ tick の状態が一致する
    var same = 0, compared = 0;
    guestRec.stateJson.forEach((tick, json) {
      final h = hostRec.stateJson[tick];
      if (h != null) {
        compared++;
        if (h == json) same++;
      }
    });
    expect(compared, greaterThan(30));
    expect(same, compared, reason: 'ホストとゲストの状態が食い違っている');

    // ゲストのキー入力が右の選手を動かす（右の選手は A で前へ = 左へ）
    final before = (guestRec.states.last.world as FencingWorld).players[1].x;
    guest.setKeys(const KeyState(l: true));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    guest.setKeys(const KeyState());
    final after = (guestRec.states.last.world as FencingWorld).players[1].x;
    expect(after, lessThan(before - 20), reason: 'ゲストの入力が反映されない');

    // 切断 → ホストは一時停止、ゲストは自動で再接続 → 同じ状態から再開
    guest.simulateDrop();
    await waitUntil('一時停止', () => host.engine?.state.paused == true);
    expect(hostRec.room?.players[1].connected, isFalse);
    final frozen = jsonEncode(host.engine!.state.world.toJson());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(jsonEncode(host.engine!.state.world.toJson()), frozen, reason: '一時停止中に試合が進んだ');
    await waitUntil('再接続', () => guestRec.joined == 2 && hostRec.room?.players[1].connected == true);
    expect(guestRec.reconnecting, 1);
    expect(host.engine!.state.resumeTimer, greaterThan(0), reason: '再開前のカウントダウンがない');
    expect(jsonEncode(host.engine!.state.world.toJson()), frozen, reason: '切断前と同じ状態から再開していない');

    // 退出: 残ったホストはロビーへ戻り、お知らせを受け取る
    guest.leave();
    await waitUntil('退出', () => hostRec.room?.notice == 'opponent_left');
    expect(hostRec.room?.phase, RoomPhase.lobby);
    expect(hostRec.room?.players[1].present, isFalse);
  });

  test('部屋を作った人が閉じると、参加した側は終了を知らされる', () async {
    final hostRec = Recorder(), guestRec = Recorder();
    host = HostSession(game: GameKind.volley, me: const Profile('ホスト', ''), listener: hostRec);
    await listen();
    final guest = GuestSession(code: host.code, me: const Profile('ゲスト', ''), listener: guestRec, findHost: (_) => null);
    await guest.connect(lo, server.port, fingerprint: identity.fingerprint);
    await waitUntil('参加', () => guestRec.joined == 1);
    host.leave();
    await waitUntil('閉じた', () => guestRec.ended.contains('closed'));
  });

  test('TLS証明書の指紋が一致しない接続を拒否する', () async {
    server = await SecureServerSocket.bind(lo, 0, identity.context);
    final link = await Link.connect(
      lo,
      server.port,
      expectedFingerprint: List.filled(64, '0').join(),
      timeout: const Duration(seconds: 2),
    );
    expect(link, isNull);
  });

  test('紙飛行機の招待: 受け取って「参加する」とその接続のまま部屋に入る', () async {
    final hostRec = Recorder(), guestRec = Recorder();
    host = HostSession(game: GameKind.badminton, me: const Profile('ホスト', ''), listener: hostRec);
    await listen();
    // 招待される側の待ち受け
    final inviteeServer = await SecureServerSocket.bind(lo, 0, identity.context);
    final got = Completer<(Msg, Link)>();
    inviteeServer.listen((s) {
      final link = Link(s);
      link.onMessage = (m) {
        link.onMessage = null;
        got.complete((m, link));
      };
    });
    await host.sendInvite(address: lo, port: inviteeServer.port, fingerprint: identity.fingerprint, peerName: 'ゲスト', y: 0.4, delay: 1.2);
    final (msg, link) = await got.future.timeout(const Duration(seconds: 5));
    expect(msg['t'], 'invite');
    expect(msg['code'], host.code);
    expect(msg['game'], 'badminton');
    expect(msg['delay'], 1.2);
    final guest = GuestSession(code: msg['code'] as String, me: const Profile('ゲスト', ''), listener: guestRec, findHost: (_) => null);
    guest.adopt(link);
    await waitUntil('招待で参加', () => guestRec.joined == 1 && hostRec.room?.players[1].present == true);
    await inviteeServer.close();
  });

  test('UDP のお知らせで、同じPCの2つの PONG! がお互いを見つける', () async {
    host = HostSession(game: GameKind.volley, me: const Profile('-', ''), listener: Recorder());
    await listen();
    final a = Discovery(udpPort: 47599, interval: const Duration(milliseconds: 200));
    final b = Discovery(udpPort: 47599, interval: const Duration(milliseconds: 200));
    await a.start(name: 'えー', avatar: '', tcpPort: 1111, fingerprint: identity.fingerprint);
    await b.start(name: 'びー', avatar: '', tcpPort: 2222, fingerprint: identity.fingerprint);
    await waitUntil('発見', () => a.peers.any((p) => p.name == 'びー') && b.peers.any((p) => p.name == 'えー'));
    b.advertise(name: 'びー', avatar: '', state: PeerState.host, code: 'KQTE', game: GameKind.boxing);
    await waitUntil('部屋の広告', () => a.peerWithCode('KQTE')?.port == 2222);
    expect(a.peerWithCode('KQTE')!.game, GameKind.boxing);
    a.dispose();
    b.dispose();
  });

  test('ブロードキャストが届かない環境でも、直接の返事でお互いを見つける', () async {
    host = HostSession(game: GameKind.volley, me: const Profile('-', ''), listener: Recorder());
    await listen();
    // 共有ポート宛ての 127.0.0.1 は片方にしか届かない。届いた側が相手専用のポートへ返事をする
    final a = Discovery(udpPort: 47598, interval: const Duration(milliseconds: 200), loopbackOnly: true);
    final b = Discovery(udpPort: 47598, interval: const Duration(milliseconds: 200), loopbackOnly: true);
    await a.start(name: 'えー', avatar: '', tcpPort: 1111, fingerprint: identity.fingerprint);
    await b.start(name: 'びー', avatar: '', tcpPort: 2222, fingerprint: identity.fingerprint);
    await waitUntil('発見', () => a.peers.any((p) => p.name == 'びー') && b.peers.any((p) => p.name == 'えー'));
    a.dispose();
    b.dispose();
  });
}
