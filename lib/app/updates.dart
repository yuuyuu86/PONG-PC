import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'version.dart';

/// 新しい版のお知らせ。起動時に GitHub Releases の最新版を1回だけ確かめる。
/// インストールは利用者がダウンロードページから行う（自動では入れかえない）。
/// オフラインや失敗したときは何も知らせない。
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({this.fetch});

  /// 最新版の情報を取ってくる（テストで差しかえる）。(タグ, ページの URL) を返す
  final Future<(String, String)?> Function()? fetch;

  /// 自分より新しい版（なければ null）
  String? latest;
  String url = AppVersion.releasesPage;
  bool checking = false;

  /// 確かめた結果（設定画面の「新しい版を確かめる」用）。null はまだ確かめていない
  bool? upToDate;

  Future<void> check() async {
    if (checking) return;
    checking = true;
    notifyListeners();
    try {
      final r = await (fetch ?? _fromGitHub)();
      if (r != null) {
        final (tag, page) = r;
        final newer = AppVersion.compare(tag, AppVersion.app) > 0;
        latest = newer ? tag.replaceFirst(RegExp('^v'), '') : null;
        url = page;
        upToDate = !newer;
      }
    } catch (_) {
      // 失敗は知らせない
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  static Future<(String, String)?> _fromGitHub() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/${AppVersion.repo}/releases/latest'));
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'PONG-PC/${AppVersion.app}')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      final tag = body['tag_name'];
      if (tag is! String) return null;
      return (tag, body['html_url'] as String? ?? AppVersion.releasesPage);
    } finally {
      client.close(force: true);
    }
  }

  /// ダウンロードページをブラウザで開く
  Future<void> openDownloadPage([String? page]) async {
    try {
      await launchUrl(Uri.parse(page ?? url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
