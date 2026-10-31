/// アプリの版と、PC どうしの通信の版。
///
/// - [app] は pubspec.yaml の version と同じにする（test/version_test.dart で確かめる）。
/// - [protocol] は、古い版と通信できなくなる変更（メッセージの意味や必須項目が変わる）をしたときだけ 1 上げる。
///   項目を足すだけなら上げずに、[features] に名前を足して、相手が対応しているかで出し分ける。
abstract final class AppVersion {
  static const app = '1.1.0';
  static const protocol = 1;

  /// この版が対応している、あとから足した機能
  /// - rule: 部屋を作るときのルール選択
  /// - swap: 待機中の左右の入れかえ
  static const features = ['rule', 'swap'];

  /// GitHub のリポジトリ（新しい版のお知らせとダウンロード先）
  static const repo = 'yuuyuu86/PONG-PC';
  static const releasesPage = 'https://github.com/$repo/releases/latest';

  /// '1.2.10' のような版を比べる。a が新しければ正、同じなら 0。読めない部分は 0 とみなす
  static int compare(String a, String b) {
    List<int> parts(String v) => v.replaceFirst(RegExp('^v'), '').split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }
}
