import 'package:flutter/services.dart';

import '../games/core/common.dart';

/// 試合で使う4つの操作
enum GameAction {
  left('左へ', PhysicalKeyboardKey.keyA, 'A'),
  right('右へ', PhysicalKeyboardKey.keyD, 'D'),
  jump('ジャンプ・パリィ・ガード', PhysicalKeyboardKey.space, 'Space'),
  action('打つ・突き・パンチ', PhysicalKeyboardKey.keyJ, 'J');

  const GameAction(this.label, this.defaultKey, this.defaultLabel);
  final String label;
  final PhysicalKeyboardKey defaultKey;
  final String defaultLabel;
}

/// キーの割り当て。物理キーと、画面に出す名前の組。
class KeyBindings {
  const KeyBindings(this.keys, this.labels);

  static final standard = KeyBindings(
    {for (final a in GameAction.values) a: a.defaultKey},
    {for (final a in GameAction.values) a: a.defaultLabel},
  );

  final Map<GameAction, PhysicalKeyboardKey> keys;
  final Map<GameAction, String> labels;

  PhysicalKeyboardKey operator [](GameAction a) => keys[a] ?? a.defaultKey;
  String label(GameAction a) => labels[a] ?? a.defaultLabel;

  bool get isStandard => GameAction.values.every((a) => this[a] == a.defaultKey);

  /// 説明文のキー名（A / D / J / Space）を、いまの割り当てに置き換える
  String describe(String text) => text.replaceAllMapped(RegExp(r'Space|\bA\b|\bD\b|\bJ\b'), (m) => switch (m[0]) {
        'A' => label(GameAction.left),
        'D' => label(GameAction.right),
        'J' => label(GameAction.action),
        _ => label(GameAction.jump),
      });

  /// キーの名前（押したときに分かる文字。分からなければ物理キーの名前）
  static String nameOf(KeyEvent e) {
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space) return 'Space';
    final l = k.keyLabel;
    if (l.trim().isNotEmpty) return l.length == 1 ? l.toUpperCase() : l;
    return e.physicalKey.debugName ?? '?';
  }
}

/// キーボード入力。試合画面にいる間だけゲーム操作としてキーを受け取り、ほかの画面ではキーを奪わない。
/// 押しっぱなしは「押している状態」、連打は「押した回数」で表す。
/// 物理キーで見るので、日本語入力やキー配列に関係なく、割り当てたキーの位置で動く（最初は A / D / J / Space）。
class GameKeyboard {
  GameKeyboard(this.onChange, {KeyBindings Function()? bindings}) : _bindings = bindings ?? (() => KeyBindings.standard) {
    HardwareKeyboard.instance.addHandler(_handle);
  }

  final void Function(KeyState) onChange;
  final KeyBindings Function() _bindings;
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
    final b = _bindings();
    if (!_active || !GameAction.values.any((a) => b[a] == k)) {
      return false;
    }
    final mods = HardwareKeyboard.instance;
    if (mods.isMetaPressed || mods.isControlPressed || mods.isAltPressed) return false;
    if (e is KeyDownEvent) {
      if (_held.add(k)) {
        if (k == b[GameAction.jump]) state = _with(jc: state.jc + 1);
        if (k == b[GameAction.action]) state = _with(ac: state.ac + 1);
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
    final b = _bindings();
    state = KeyState(
      l: _held.contains(b[GameAction.left]),
      r: _held.contains(b[GameAction.right]),
      j: _held.contains(b[GameAction.jump]),
      a: _held.contains(b[GameAction.action]),
      jc: state.jc,
      ac: state.ac,
    );
    onChange(state);
  }

  void dispose() => HardwareKeyboard.instance.removeHandler(_handle);
}
