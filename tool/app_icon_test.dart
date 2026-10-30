// アプリアイコンの PNG / ICO を作り直す: flutter test tool/app_icon_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pong_pc/ui/logo.dart';

Future<Uint8List> render(int px) async {
  final rec = ui.PictureRecorder();
  const AppIconPainter().paint(Canvas(rec), Size(px.toDouble(), px.toDouble()));
  final image = await rec.endRecording().toImage(px, px);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// PNG をそのまま入れた ICO（Vista 以降で読める）
Uint8List ico(List<(int, Uint8List)> images) {
  final head = BytesBuilder();
  final body = BytesBuilder();
  final h = ByteData(6)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  head.add(h.buffer.asUint8List());
  var offset = 6 + 16 * images.length;
  for (final (px, png) in images) {
    final e = ByteData(16)
      ..setUint8(0, px >= 256 ? 0 : px)
      ..setUint8(1, px >= 256 ? 0 : px)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, png.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    head.add(e.buffer.asUint8List());
    body.add(png);
    offset += png.length;
  }
  return (head..add(body.takeBytes())).takeBytes();
}

void main() {
  test('アプリアイコンを書き出す', () async {
    const mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    final win = <(int, Uint8List)>[];
    for (final px in const [16, 32, 48, 64, 128, 256, 512, 1024]) {
      final png = await render(px);
      if (px != 48) File('$mac/app_icon_$px.png').writeAsBytesSync(png);
      if (const [16, 32, 48, 64, 256].contains(px)) win.add((px, png));
    }
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico(win));
  });
}
