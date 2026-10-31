import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../avatar/avatar.dart';
import 'keyboard.dart';
import 'records.dart';

/// このPCに保存する設定（スマホ版 AppSettings と同じ形）。
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async => AppSettings._(await SharedPreferences.getInstance()).._migrate();

  /// 保存データの形の版。保存する形を変えたら 1 上げ、[_migrate] に古い形からの読み替えを足す。
  /// （1.1.0 より前は版を持っていないので 0 とみなす。0 → 1 で変わった形はない）
  static const dataVersion = 1;

  int get savedDataVersion => _prefs.getInt('dataVersion') ?? 0;

  /// 古い版で保存したデータを、いまの形に読み替える。新しい版で保存したデータ（版が大きい）はそのまま使う。
  void _migrate() {
    final from = savedDataVersion;
    if (from >= dataVersion) return;
    // 例: if (from < 2) { 'records' の形を変える … }
    _prefs.setInt('dataVersion', dataVersion);
  }

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

  /// 「あとで」を押した新しい版（同じ版のお知らせは出さない）
  String? get dismissedUpdate => _prefs.getString('dismissedUpdate');
  set dismissedUpdate(String? v) => _set(() => v == null ? _prefs.remove('dismissedUpdate') : _prefs.setString('dismissedUpdate', v));

  bool get soundOn => _prefs.getBool('soundOn') ?? true;
  set soundOn(bool v) => _set(() => _prefs.setBool('soundOn', v));

  double get volume => _prefs.getDouble('volume') ?? 0.7;
  set volume(double v) => _set(() => _prefs.setDouble('volume', v));

  /// キーの割り当て（'物理キーの番号|表示名'）
  KeyBindings get keys {
    final keys = <GameAction, PhysicalKeyboardKey>{};
    final labels = <GameAction, String>{};
    for (final a in GameAction.values) {
      final raw = _prefs.getString('key_${a.name}')?.split('|');
      final usage = raw == null ? null : int.tryParse(raw[0]);
      if (usage == null || raw!.length < 2) continue;
      keys[a] = PhysicalKeyboardKey(usage);
      labels[a] = raw.sublist(1).join('|');
    }
    return KeyBindings(keys, labels);
  }

  /// [action] に [key] を割り当てる。ほかの操作が同じキーを使っていたら、入れ替える。
  void bindKey(GameAction action, PhysicalKeyboardKey key, String label) {
    final now = keys;
    for (final other in GameAction.values) {
      if (other != action && now[other] == key) {
        _prefs.setString('key_${other.name}', '${now[action].usbHidUsage}|${now.label(action)}');
      }
    }
    _set(() => _prefs.setString('key_${action.name}', '${key.usbHidUsage}|$label'));
  }

  void resetKeys() {
    for (final a in GameAction.values) {
      _prefs.remove('key_${a.name}');
    }
    notifyListeners();
  }

  /// 対戦結果の記録（新しい順、最大 [maxRecords] 件）
  static const maxRecords = 200;
  List<MatchRecord> get records => MatchRecord.decodeList(_prefs.getString('records'));

  void addRecord(MatchRecord r) {
    final list = [r, ...records].take(maxRecords).toList();
    _set(() => _prefs.setString('records', MatchRecord.encodeList(list)));
  }

  void clearRecords() => _set(() => _prefs.remove('records'));

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
