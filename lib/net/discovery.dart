import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../games/core/catalog.dart';

enum PeerState { idle, host, full, busy }

/// 同じWi-Fiにいる PONG! のPC
class Peer {
  Peer({required this.id, required this.name, required this.avatar, required this.state, this.code, this.game, required this.fingerprint, required this.address, required this.port, required this.lastSeen});

  final String id;
  final String name;
  final String avatar;
  final PeerState state;
  final String? code;
  final GameKind? game;
  final String fingerprint;
  final InternetAddress address;
  final int port;
  final DateTime lastSeen;

  bool sameAs(Peer o) => o.id == id && o.name == name && o.avatar == avatar && o.state == state && o.code == code && o.game == game && o.fingerprint == fingerprint && o.port == port;
}

enum DiscoveryStatus { starting, ready, failed }

/// 同じWi-Fi（同じネットワーク）の PONG! を見つける。
/// 1秒ごとに UDP ブロードキャストで「自分はここにいる（名前・状態・部屋コード・TCP の待ち受けポート）」を知らせ、
/// 届いたお知らせから一覧を作る。サーバーは要らず、Mac と Windows で同じしくみが動く。
class Discovery extends ChangeNotifier {
  Discovery({this.udpPort = defaultPort, this.interval = const Duration(seconds: 1), this.loopbackOnly = false});

  static const defaultPort = 47521;
  static const _magic = 'pong-pc/2';

  final int udpPort;
  final Duration interval;

  /// ブロードキャストを使わず 127.0.0.1 にだけ送る（ブロードキャストできない環境を再現するテスト用）
  final bool loopbackOnly;
  final myId = List.generate(8, (_) => math.Random().nextInt(16).toRadixString(16)).join();

  List<Peer> get peers => List.unmodifiable(_peers.values.toList()..sort((a, b) => a.name.compareTo(b.name)));
  DiscoveryStatus status = DiscoveryStatus.starting;
  String? error;

  final _peers = <String, Peer>{};
  RawDatagramSocket? _socket;

  /// 自分専用の UDP（返事を受け取る用）。ブロードキャストが届かない向きがあっても、
  /// 片方から相手が見えれば、ここへ直接お知らせを返して両方から見えるようにする。
  /// 同じPCで2つ起動したときも、共有ポート宛ての 127.0.0.1 は片方にしか届かないので、これで補う。
  RawDatagramSocket? _direct;
  final _lastReply = <String, DateTime>{};

  /// お知らせを送るだけの UDP（送り先ごとに1つ）。受け取り用とは分ける。
  /// ブロードキャストを許さないネットワークでは送信が失敗し、そのソケットが使えなくなることがあるため、
  /// 失敗したら作り直し、受け取り用のソケットには影響させない。
  final _senders = <String, RawDatagramSocket>{};
  final _opening = <String>{};
  Timer? _timer;
  var _advert = <String, Object?>{};
  List<InternetAddress> _targets = [InternetAddress('255.255.255.255')];

  Future<void> start({required String name, required String avatar, required int tcpPort, required String fingerprint}) async {
    _advert = {'m': _magic, 'id': myId, 'name': name, 'avatar': avatar, 'state': PeerState.idle.name, 'port': tcpPort, 'fp': fingerprint};
    try {
      // 同じPCで2つ起動しても受け取れるよう、ポートを共有する（Windows は reuseAddress で共有できる）
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort, reuseAddress: true, reusePort: !Platform.isWindows);
      s.broadcastEnabled = true;
      _listen(s);
      _socket = s;
      final d = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _listen(d);
      _direct = d;
      _advert['up'] = d.port;
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

  void _listen(RawDatagramSocket s) {
    s.listen(
      (e) {
        if (e == RawSocketEvent.read) _receive(s);
      },
      onError: (Object _) {},
    );
  }

  /// 送り先: 全体へのブロードキャストと、各ネットワークの x.y.z.255（多くの家庭・学校の Wi-Fi はこれで届く）
  Future<void> _refreshTargets() async {
    final targets = <String>{if (!loopbackOnly) '255.255.255.255', '127.0.0.1'};
    if (loopbackOnly) {
      _targets = [InternetAddress.loopbackIPv4];
      return;
    }
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
    final next = <String, Object?>{..._advert, 'name': name, 'avatar': avatar, 'state': state.name, 'code': code, 'game': game?.name};
    if (mapEquals(next, _advert)) return;
    _advert = next;
    _beacon();
  }

  void _beacon() {
    if (_socket == null) return;
    final data = utf8.encode(jsonEncode(_advert));
    for (final t in _targets) {
      final sender = _senders[t.address];
      if (sender == null) {
        _openSender(t.address);
        continue;
      }
      try {
        sender.send(data, t, udpPort);
      } catch (_) {
        _dropSender(t.address);
      }
    }
  }

  Future<void> _openSender(String target) async {
    if (!_opening.add(target)) return;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      s.broadcastEnabled = true;
      // 送信の失敗はここに届く。次のお知らせのときに作り直す
      s.listen((_) {}, onError: (Object _) => _dropSender(target), onDone: () => _dropSender(target));
      if (_timer == null) {
        s.close();
      } else {
        _senders[target] = s;
        try {
          s.send(utf8.encode(jsonEncode(_advert)), InternetAddress(target), udpPort);
        } catch (_) {
          _dropSender(target);
        }
      }
    } catch (_) {
      // 送れない送り先はあきらめて、次の機会にまた試す
    } finally {
      _opening.remove(target);
    }
  }

  void _dropSender(String target) {
    final s = _senders.remove(target);
    try {
      s?.close();
    } catch (_) {}
  }

  /// 相手専用の UDP へ自分のお知らせを直接返す（同じ相手には間隔をあけて）
  void _replyTo(String id, InternetAddress address, int port) {
    final d = _direct;
    final now = DateTime.now();
    final last = _lastReply[id];
    if (d == null || (last != null && now.difference(last) < interval * 2)) return;
    _lastReply[id] = now;
    try {
      d.send(utf8.encode(jsonEncode(_advert)), address, port);
    } catch (_) {}
  }

  void _receive(RawDatagramSocket s) {
    Datagram? d;
    var changed = false;
    while ((d = s.receive()) != null) {
      try {
        final m = jsonDecode(utf8.decode(d!.data));
        if (m is! Map || m['m'] != _magic || m['id'] == myId) continue;
        final id = m['id'] as String;
        final fingerprint = m['fp'];
        if (fingerprint is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) continue;
        final peer = Peer(
          id: id,
          name: (m['name'] as String?) ?? 'PC',
          avatar: (m['avatar'] as String?) ?? '',
          state: PeerState.values.asNameMap()[m['state']] ?? PeerState.busy,
          code: m['code'] as String?,
          game: GameKind.values.asNameMap()[m['game']],
          fingerprint: fingerprint,
          // 同じPCから届いたお知らせ（127.0.0.1 経由など）でも、そのアドレスでつながる
          address: d.address,
          port: (m['port'] as num).toInt(),
          lastSeen: DateTime.now(),
        );
        final old = _peers[id];
        _peers[id] = peer;
        final up = m['up'];
        if (up is num) _replyTo(id, d.address, up.toInt());
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
    _timer = null;
    for (final t in [..._senders.keys]) {
      _dropSender(t);
    }
    _socket?.close();
    _direct?.close();
    super.dispose();
  }
}
