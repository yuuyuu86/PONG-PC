import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_model.dart';
import '../app/services.dart';
import '../app/settings.dart';
import '../avatar/avatar.dart';
import '../avatar/avatar_editor.dart';
import '../ui/doodle.dart';
import '../ui/widgets.dart';
import 'root.dart';

// スマホ版のプロフィール機能（register_screen / profile_screen / ホームの _PlayerBadge）を PC 向けに移植したもの。

/// 手描きの枠の入力欄（スマホ版 DoodleTextField）
class DoodleTextField extends StatelessWidget {
  const DoodleTextField({super.key, required this.controller, this.hint, this.onChanged, this.onSubmitted, this.maxLength, this.style, this.textAlign = TextAlign.start});

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return DoodleBox(
      seed: 71,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        maxLength: maxLength,
        autocorrect: false,
        textAlign: textAlign,
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\r\t]'))],
        style: style ?? const TextStyle(fontSize: 19, color: Palette.ink),
        decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Palette.pencil), border: InputBorder.none, counterText: ''),
      ),
    );
  }
}

/// 初めて開いたときのプレイヤー登録。名前と見た目は対戦相手の画面や招待状に表示される。
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  bool _touched = false;
  Avatar _avatar = Avatar.random();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _problem => AppSettings.validateName(_name.text);

  void _start() {
    setState(() => _touched = true);
    if (_problem != null) return;
    final s = Services.of(context);
    s.settings.completeRegistration(_name.text, _avatar);
    s.model.go(Screen.home);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final preview = _name.text.trim();
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DoodleHeading('プレイヤー登録'),
        const SizedBox(height: 10),
        const Text('あなたの名前と見た目を決めてください。\n対戦するとき、相手の画面に表示されます。', style: TextStyle(fontSize: 17, height: 1.45)),
        const SizedBox(height: 20),
        DoodleTextField(
          controller: _name,
          hint: '名前 (${AppSettings.maxNameLength}文字まで)',
          maxLength: AppSettings.maxNameLength,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, color: Palette.ink),
          onChanged: (_) => setState(() => _touched = true),
          onSubmitted: (_) => _start(),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 26,
          child: _touched && problem != null
              ? Semantics(liveRegion: true, child: StatusLine(state: StatusKind.bad, text: problem))
              : Text('${preview.characters.length} / ${AppSettings.maxNameLength}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 15, color: Palette.pencil)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: DoodleButton(
            label: '名前をおまかせ', icon: Icons.casino_outlined, fontSize: 17, seed: 161,
            onPressed: () {
              final n = AppSettings.suggestName();
              _name.value = TextEditingValue(text: n, selection: TextSelection.collapsed(offset: n.length));
              setState(() => _touched = true);
            },
          ),
        ),
        const SizedBox(height: 30),
        DoodleBox(
          seed: 162, dashed: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('相手の画面ではこう見えます', style: TextStyle(fontSize: 15, color: Palette.pencil)),
            const SizedBox(height: 8),
            PlayerTag(avatar: _avatar, name: preview.isEmpty ? '―' : preview, trailing: '(接続中)'),
          ]),
        ),
      ],
    );
    final action = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        DoodleButton(label: 'はじめる', icon: Icons.arrow_forward_rounded, primary: true, seed: 163, onPressed: problem == null ? _start : null),
        const SizedBox(height: 12),
        const Text('名前と見た目は、あとからトップ画面で変えられます。', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Palette.pencil)),
      ],
    );
    final appearance = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DoodleHeading('みため'),
        const SizedBox(height: 12),
        AvatarEditor(value: _avatar, onChanged: (a) => setState(() => _avatar = a)),
      ],
    );
    return DoodleScaffold(
      showBack: false,
      child: PageBody(
        maxWidth: 1040,
        children: [
          const Text('ようこそ！', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
          const Text('PONG!', textAlign: TextAlign.center, style: TextStyle(fontSize: 56, height: 1.1, letterSpacing: 4)),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [identity, const SizedBox(height: 32), appearance, action]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [identity, action])),
              const SizedBox(width: 56),
              Expanded(child: appearance),
            ]);
          }),
        ],
      ),
    );
  }
}

/// プレイヤーの名前と見た目を変える画面。変更はその場で保存する（スマホ版 ProfileScreen）。
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AppSettings settings = Services.of(context).settings;
  late final _name = TextEditingController(text: settings.playerName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final problem = AppSettings.validateName(_name.text);
    return DoodleScaffold(
      title: 'プレイヤー',
      onBack: () => Services.of(context).model.go(Screen.home),
      child: PageBody(
        maxWidth: 640,
        children: [
          const DoodleHeading('なまえ'),
          const SizedBox(height: 10),
          DoodleTextField(
            controller: _name,
            hint: 'プレイヤー',
            maxLength: AppSettings.maxNameLength,
            onChanged: (v) {
              // 空欄などのときは保存せず、前の名前を残す
              if (AppSettings.validateName(v) == null) settings.playerName = v;
              setState(() {});
            },
          ),
          if (problem != null) ...[const SizedBox(height: 8), StatusLine(state: StatusKind.bad, text: '$problem (いまの名前: ${settings.playerName})')],
          const SizedBox(height: 24),
          const DoodleHeading('みため'),
          const SizedBox(height: 12),
          AvatarEditor(value: settings.avatar, onChanged: (a) => settings.avatar = a),
          const SizedBox(height: 14),
          const Text('次に部屋を作る・参加するときから、相手にも表示されます。', textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}

/// ホームの登録した名前の表示。押すとプロフィールを変えられる（スマホ版 _PlayerBadge）。
class PlayerBadge extends StatelessWidget {
  const PlayerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return Center(
      child: Semantics(
        button: true,
        label: 'プレイヤー ${s.settings.playerName}。名前と見た目を変える',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => s.model.go(Screen.profile),
            child: DoodleBox(
              seed: 171,
              dashed: true,
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AvatarIcon(avatar: s.settings.avatar, size: 44),
                  const SizedBox(width: 10),
                  Flexible(child: Text(s.settings.playerName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19))),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_rounded, color: Palette.pencil, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
