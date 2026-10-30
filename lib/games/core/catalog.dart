import '../badminton/badminton.dart';
import '../boxing/boxing.dart';
import '../fencing/fencing.dart';
import '../volley/volley.dart';
import 'common.dart';
import 'painting.dart';

class GameControl {
  const GameControl(this.key, this.label);
  final String key;
  final String label;
}

/// 収録タイトル。新しいゲームを足すときは値を1つ増やし、ルール・描画・説明を返す。
enum GameKind {
  volley(
    title: 'バレー',
    tagline: 'ジャンプとタイミングのラリー',
    summary: '高いネットを挟んで打ち合う。自分のコートで3回まで触れるので、トスを上げて跳んでスパイク！',
    ruleText: '先に5点で勝ち。得点ごとにサーブ交代。',
    controls: [
      GameControl('A / D', '左右に移動'),
      GameControl('Space', 'ジャンプ'),
      GameControl('J', '打つ（ジャンプ中の高い打点でスパイク）'),
      GameControl('後ろ + J', '真上にトス'),
    ],
  ),
  badminton(
    title: 'バドミントン',
    tagline: '失速するシャトルの落下点を読む',
    summary: 'シャトルは速く飛び出して急に失速する。入力の向きでクリアとドロップを打ち分け、高い打点ならスマッシュ。',
    ruleText: '先に5点で勝ち。1人1回で返す。得点した側がサーブ。',
    controls: [
      GameControl('A / D', '左右に移動'),
      GameControl('Space', 'ジャンプ'),
      GameControl('J', '打つ（前+J ドロップ / 後ろ+J クリア）'),
      GameControl('ジャンプ中 J', '高い打点でスマッシュ'),
    ],
  ),
  fencing(
    title: 'フェンシング',
    tagline: '間合いと突きのタイミング',
    summary: '中央線を挟んで構え、前後に間合いを測る。突きは踏み込んで届くが、パリィされると隙だらけ。',
    ruleText: '先に5点で勝ち。同時の突きは相打ち。後ろの端から出ると相手の得点。',
    controls: [
      GameControl('A / D', '前後に移動'),
      GameControl('J', '突き（踏み込む）'),
      GameControl('Space', 'パリィ（短い受け流し）'),
    ],
  ),
  boxing(
    title: 'ボクシング',
    tagline: '移動・ガード・パンチの読み合い',
    summary: 'リングで向かい合う。ガードで受け止め、相手の振りかぶりにパンチを合わせればカウンター。',
    ruleText: '体力0でKO。60秒たったら有効打が多い方の勝ち。',
    controls: [
      GameControl('A / D', '左右に移動'),
      GameControl('J', 'パンチ'),
      GameControl('Space 長押し', 'ガード'),
    ],
  );

  const GameKind({required this.title, required this.tagline, required this.summary, required this.ruleText, required this.controls});

  final String title;
  final String tagline;
  final String summary;
  final String ruleText;
  final List<GameControl> controls;

  SportRules get rules => switch (this) {
        volley => VolleyRules.instance,
        badminton => BadmintonRules.instance,
        fencing => FencingRules.instance,
        boxing => BoxingRules.instance,
      };

  SportPainter get painter => switch (this) {
        volley => const VolleyPainter(),
        badminton => const BadmintonPainter(),
        fencing => const FencingPainter(),
        boxing => const BoxingPainter(),
      };

  /// 部屋を作るときに選べるルール。ボクシングは試合時間（秒）、ほかは何点先取か。
  List<int> get ruleChoices => this == boxing ? const [30, 60, 90] : const [3, 5, 7, 11];

  /// 何も選ばないときのルール（これまでと同じ）
  int get defaultRule => this == boxing ? 60 : 5;

  /// 選んだルールに合わせた説明
  String ruleTextFor(int rule) => ruleText.replaceFirst(this == boxing ? '60秒' : '先に5点', this == boxing ? '$rule秒' : '先に$rule点');

  String ruleLabel(int rule) => this == boxing ? '$rule秒' : '$rule点先取';

  /// 結果やスコアの単位（ボクシングは有効打の数）
  String? get scoreUnit => this == boxing ? '有効打' : null;
}
