import 'package:flutter/services.dart';

import '../games/core/common.dart';

/// キーボード入力。試合画面にいる間だけゲーム操作としてキーを受け取り、ほかの画面ではキーを奪わない。
/// 押しっぱなしは「押している状態」、連打は「押した回数」で表す。
/// 物理キーで見るので、日本語入力やキー配列に関係なく A / D / J / Space の位置で動く。
class GameKeyboard {
  GameKeyboard(this.onChange) {
    HardwareKeyboard.instance.addHandler(_handle);
  }

  final void Function(KeyState) onChange;
  final _held = <PhysicalKeyboardKey>{};
  KeyState state = const KeyState();
  bool _active = false;

  bool get active => _active;
  set active(bool v) {
    if (_active == v) return;
    _active = v;
    if (!v) releaseAll();
  }

  bool _handle(KeyEvent e) {
    final k = e.physicalKey;
    if (!_active || !(k == PhysicalKeyboardKey.keyA || k == PhysicalKeyboardKey.keyD || k == PhysicalKeyboardKey.keyJ || k == PhysicalKeyboardKey.space)) {
      return false;
    }
    final mods = HardwareKeyboard.instance;
    if (mods.isMetaPressed || mods.isControlPressed || mods.isAltPressed) return false;
    if (e is KeyDownEvent) {
      if (_held.add(k)) {
        if (k == PhysicalKeyboardKey.space) state = _with(jc: state.jc + 1);
        if (k == PhysicalKeyboardKey.keyJ) state = _with(ac: state.ac + 1);
      }
    } else if (e is KeyUpEvent) {
      _held.remove(k);
    }
    // KeyRepeatEvent（押しっぱなしの連続入力）は数えない
    _sync();
    return true; // 試合中は Space などをほかの部品に渡さない
  }

  /// ウィンドウから離れたら押しっぱなしを解除（キーが戻らなくなるのを防ぐ）
  void releaseAll() {
    if (_held.isEmpty) return;
    _held.clear();
    _sync();
  }

  KeyState _with({int? jc, int? ac}) => KeyState(l: state.l, r: state.r, j: state.j, a: state.a, jc: jc ?? state.jc, ac: ac ?? state.ac);

  void _sync() {
    state = KeyState(
      l: _held.contains(PhysicalKeyboardKey.keyA),
      r: _held.contains(PhysicalKeyboardKey.keyD),
      j: _held.contains(PhysicalKeyboardKey.space),
      a: _held.contains(PhysicalKeyboardKey.keyJ),
      jc: state.jc,
      ac: state.ac,
    );
    onChange(state);
  }

  void dispose() => HardwareKeyboard.instance.removeHandler(_handle);
}
