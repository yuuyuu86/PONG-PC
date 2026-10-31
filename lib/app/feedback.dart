import 'package:audioplayers/audioplayers.dart';

import 'settings.dart';

enum Sound { hit, bounce, point, lose, win, tap }

/// 効果音（スマホ版と同じ音）。設定でミュート・音量を切り替えられる。
class GameFeedback {
  GameFeedback(this.settings);

  final AppSettings settings;
  final _pools = <Sound, AudioPool>{};

  Future<void> init() async {
    for (final s in Sound.values) {
      try {
        _pools[s] = await AudioPool.create(
          source: AssetSource('sounds/${s.name}.wav'),
          maxPlayers: s == Sound.hit || s == Sound.bounce ? 3 : 1,
        );
      } catch (_) {
        // 音が出せない環境でもゲームは続ける
      }
    }
  }

  void play(Sound s, {double gain = 1}) {
    if (!settings.soundOn || settings.volume <= 0) return;
    _pools[s]?.start(volume: (settings.volume * gain).clamp(0, 1)).catchError((_) => () async {});
  }

  /// 試合のイベントを音に割り当てる
  void playEvent(String type, {int? side, required int you}) {
    switch (type) {
      case 'serve' || 'bump' || 'toss' || 'drive' || 'drop' || 'clear' || 'swing' || 'lunge':
        play(Sound.hit, gain: 0.7);
      case 'spike' || 'smash' || 'punch' || 'counter' || 'touche':
        play(Sound.hit);
      case 'net' || 'land' || 'block' || 'parry' || 'clash' || 'guard':
        play(Sound.bounce, gain: 0.8);
      case 'point':
        play(Sound.point, gain: 0.8);
      case 'start':
        play(Sound.tap);
      case 'end':
        play(side == -1 ? Sound.point : (side == you ? Sound.win : Sound.lose));
    }
  }
}
