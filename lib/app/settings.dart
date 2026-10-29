import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../avatar/avatar.dart';

/// このPCに保存する設定（スマホ版 AppSettings と同じ形）。
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async => AppSettings._(await SharedPreferences.getInstance());

  static const maxNameLength = 12;

  String get playerName {
    final saved = _prefs.getString('playerName');
    if (saved != null && saved.isNotEmpty) return saved;
    final name = suggestName();
    _prefs.setString('playerName', name);
    return name;
  }

  set playerName(String v) => _set(() => _prefs.setString('playerName', v.trim()));

  /// 棒人間の見た目（[Avatar.encode] の文字列）
  Avatar get avatar {
    final raw = _prefs.getString('avatar');
    if (raw != null) return Avatar.decode(raw);
    final a = Avatar.random();
    _prefs.setString('avatar', a.encode());
    return a;
  }

  set avatar(Avatar v) => _set(() => _prefs.setString('avatar', v.encode()));

  /// 初回起動時のプレイヤー登録を済ませたか（スマホ版と同じ）
  bool get registered => _prefs.getBool('registered') ?? false;

  void completeRegistration(String name, Avatar avatar) {
    _prefs.setString('playerName', name.trim());
    _prefs.setString('avatar', avatar.encode());
    _set(() => _prefs.setBool('registered', true));
  }

  /// 名前に問題があれば利用者向けの説明を返す。
  static String? validateName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return '名前を入れてください';
    if (name.characters.length > maxNameLength) return '名前は$maxNameLength文字までです';
    return null;
  }

  static const _nameIdeas = ['スパイク', 'スマッシュ', 'ラリー', 'エース', 'ボレー', 'ジャブ', 'パリィ', 'ロブ', 'サーブ', 'トス'];

  /// 「おまかせ」で使う名前の候補
  static String suggestName([math.Random? rnd]) {
    final r = rnd ?? math.Random();
    return '${_nameIdeas[r.nextInt(_nameIdeas.length)]}${r.nextInt(90) + 10}';
  }

  bool get soundOn => _prefs.getBool('soundOn') ?? true;
  set soundOn(bool v) => _set(() => _prefs.setBool('soundOn', v));

  double get volume => _prefs.getDouble('volume') ?? 0.7;
  set volume(double v) => _set(() => _prefs.setDouble('volume', v));

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
