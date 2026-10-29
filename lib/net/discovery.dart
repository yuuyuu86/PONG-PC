import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../games/core/catalog.dart';

enum PeerState { idle, host, full, busy }

/// 同じWi-Fiにいる PONG! のPC
class Peer {
  Peer({required this.id, required this.name, required this.avatar, required this.state, this.code, this.game, required this.address, required this.port, required this.lastSeen});

  final String id;
  final String name;
  final String avatar;
  final PeerState state;
  final String? code;
  final GameKind? game;
  final InternetAddress address;
  final int port;
  final DateTime lastSeen;

  bool sameAs(Peer o) => o.id == id && o.name == name && o.avatar == avatar && o.state == state && o.code == code && o.game == game && o.port == port;
}

enum DiscoveryStatus { starting, ready, failed }

/// 同じWi-Fi（同じネットワーク）の PONG! を見つける。
/// 1秒ごとに UDP ブロードキャストで「自分はここにいる（名前・状態・部屋コード・TCP の待ち受けポート）」を知らせ、
/// 届いたお知らせから一覧を作る。サーバーは要らず、Mac と Windows で同じしくみが動く。
class Discovery extends ChangeNotifier {
  Discovery({this.udpPort = defaultPort, this.interval = const Duration(seconds: 1)});

  static const defaultPort = 47521;
  static const _magic = 'pong-pc/1';

  final int udpPort;
  final Duration interval;
  final myId = List.generate(8, (_) => math.Random().nextInt(16).toRadixString(16)).join();

  List<Peer> get peers => List.unmodifiable(_peers.values.toList()..sort((a, b) => a.name.compareTo(b.name)));
  DiscoveryStatus status = DiscoveryStatus.starting;
  String? error;

  final _peers = <String, Peer>{};
  RawDatagramSocket? _socket;
  Timer? _timer;
  var _advert = <String, Object?>{};
  List<InternetAddress> _targets = [InternetAddress('255.255.255.255')];

  Future<void> start({required String name, required String avatar, required int tcpPort}) async {
    _advert = {'m': _magic, 'id': myId, 'name': name, 'avatar': avatar, 'state': PeerState.idle.name, 'port': tcpPort};
    try {
      // 同じPCで2つ起動しても受け取れるよう、ポートを共有する（Windows は reuseAddress で共有できる）
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort, reuseAddress: true, reusePort: !Platform.isWindows);
      s.broadcastEnabled = true;
      s.listen((e) {
        if (e == RawSocketEvent.read) _receive();
      });
      _socket = s;
      status = DiscoveryStatus.ready;
    } catch (e) {
      status = DiscoveryStatus.failed;
      error = '$e';
    }
    await _refreshTargets();
    _timer = Timer.periodic(interval, (t) {
      if (t.tick % 10 == 0) _refreshTargets();
      _beacon();
      _prune();
    });
    _beacon();
    notifyListeners();
  }

  /// 送り先: 全体へのブロードキャストと、各ネットワークの x.y.z.255（多くの家庭・学校の Wi-Fi はこれで届く）
  Future<void> _refreshTargets() async {
    final targets = <String>{'255.255.255.255', '127.0.0.1'};
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in ni.addresses) {
          if (a.isLoopback) continue;
          final p = a.address.split('.');
          if (p.length == 4) targets.add('${p[0]}.${p[1]}.${p[2]}.255');
        }
      }
    } catch (_) {}
    _targets = [for (final t in targets) InternetAddress(t)];
  }

  /// 自分の状態（待機中 / 部屋あり / 満員 / 試合中）を知らせ直す
  void advertise({required String name, required String avatar, required PeerState state, String? code, GameKind? game}) {
    final next = {..._advert, 'name': name, 'avatar': avatar, 'state': state.name, 'code': code, 'game': game?.name};
    if (mapEquals(next, _advert)) return;
    _advert = next;
    _beacon();
  }

  void _beacon() {
    final s = _socket;
    if (s == null) return;
    final data = utf8.encode(jsonEncode(_advert));
    for (final t in _targets) {
      try {
        s.send(data, t, udpPort);
      } catch (_) {}
    }
  }

  void _receive() {
    final s = _socket;
    if (s == null) return;
    Datagram? d;
    var changed = false;
    while ((d = s.receive()) != null) {
      try {
        final m = jsonDecode(utf8.decode(d!.data));
        if (m is! Map || m['m'] != _magic || m['id'] == myId) continue;
        final id = m['id'] as String;
        final peer = Peer(
          id: id,
          name: (m['name'] as String?) ?? 'PC',
          avatar: (m['avatar'] as String?) ?? '',
          state: PeerState.values.asNameMap()[m['state']] ?? PeerState.busy,
          code: m['code'] as String?,
          game: GameKind.values.asNameMap()[m['game']],
          // 同じPCから届いたお知らせ（127.0.0.1 経由など）でも、そのアドレスでつながる
          address: d.address,
          port: (m['port'] as num).toInt(),
          lastSeen: DateTime.now(),
        );
        final old = _peers[id];
        _peers[id] = peer;
        if (old == null || !old.sameAs(peer)) changed = true;
      } catch (_) {}
    }
    if (changed) notifyListeners();
  }

  void _prune() {
    final now = DateTime.now();
    final before = _peers.length;
    _peers.removeWhere((_, p) => now.difference(p.lastSeen) > interval * 3.5);
    if (_peers.length != before) notifyListeners();
  }

  Peer? peerWithCode(String code) {
    for (final p in _peers.values) {
      if (p.code == code && (p.state == PeerState.host || p.state == PeerState.full)) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _socket?.close();
    super.dispose();
  }
}
