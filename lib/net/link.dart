import 'dart:async';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';

import 'wire.dart';

/// 相手のPCとの1本の TCP 接続
class Link {
  Link(this._socket) {
    try {
      _socket.setOption(
        SocketOption.tcpNoDelay,
        true,
      ); // 小さなメッセージをすぐ送る（入力の遅れを減らす）
    } catch (_) {}
    _sub = _socket.listen(
      _onData,
      onError: (_) => close(),
      onDone: close,
      cancelOnError: true,
    );
  }

  /// つなぐ。timeout 以内につながらなければ null。
  static Future<Link?> connect(
    InternetAddress host,
    int port, {
    required String expectedFingerprint,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final secure = await SecureSocket.secure(
        socket,
        context: SecurityContext(withTrustedRoots: false),
        onBadCertificate: (certificate) =>
            CryptoUtils.getHash(certificate.der).toLowerCase() ==
            expectedFingerprint.toLowerCase(),
      ).timeout(timeout);
      return Link(secure);
    } catch (_) {
      socket?.destroy();
      return null;
    }
  }

  final SecureSocket _socket;
  late final StreamSubscription<List<int>> _sub;
  final _decoder = WireDecoder();
  void Function(Msg)? onMessage;
  void Function()? onClose;
  DateTime lastHeard = DateTime.now();
  bool _closed = false;

  bool get isClosed => _closed;

  void _onData(List<int> data) {
    lastHeard = DateTime.now();
    final msgs = _decoder.add(data);
    if (msgs == null) {
      close();
      return;
    }
    for (final m in msgs) {
      if (_closed) return;
      switch (m['t']) {
        case 'ping':
          send(const {'t': 'pong'});
        case 'pong':
          break;
        default:
          onMessage?.call(m);
      }
    }
  }

  void send(Msg m) {
    if (_closed) return;
    try {
      _socket.add(WireCodec.encode(m));
    } catch (_) {
      close();
    }
  }

  /// 一定時間何も届かなければ切れたとみなす（スリープやWi-Fiの切断はTCPだけでは気づきにくい）
  void checkAlive(Duration limit) {
    if (_closed) return;
    if (DateTime.now().difference(lastHeard) > limit) {
      close();
    } else {
      send(const {'t': 'ping'});
    }
  }

  /// 送り終わってから閉じる
  void closeSoon() => Timer(const Duration(milliseconds: 250), close);

  void close() {
    if (_closed) return;
    _closed = true;
    _sub.cancel();
    _socket.destroy();
    final cb = onClose;
    onClose = null;
    onMessage = null;
    cb?.call();
  }
}
