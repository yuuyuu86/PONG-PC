import 'package:flutter/material.dart';

import '../ui/doodle.dart';
import '../ui/widgets.dart';
import 'avatar.dart';
import 'avatar_painter.dart';

/// 棒人間の着せ替え。パーツごとに ◀ ▶ で切り替える。
class AvatarEditor extends StatelessWidget {
  const AvatarEditor({super.key, required this.value, required this.onChanged, this.horizontal = false});

  final Avatar value;
  final ValueChanged<Avatar> onChanged;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final preview = Center(
      child: Semantics(
        label: '見た目のプレビュー。${AvatarPart.values.map((p) => '${p.label} ${value.optionLabel(p)}').join('、')}',
        child: DoodleBox(seed: 181, shadow: true, padding: const EdgeInsets.fromLTRB(28, 10, 28, 6), child: AvatarView(avatar: value, size: 170)),
      ),
    );
    final options = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final part in AvatarPart.values) _PartRow(part: part, value: value, onChanged: onChanged),
      const SizedBox(height: 8),
      Align(child: DoodleButton(label: 'おまかせ', icon: Icons.casino_outlined, fontSize: 17, seed: 182, onPressed: () => onChanged(Avatar.random()))),
    ]);
    if (horizontal) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: preview), const SizedBox(width: 32), Expanded(child: options)]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [preview, const SizedBox(height: 14), options]);
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({required this.part, required this.value, required this.onChanged});

  final AvatarPart part;
  final Avatar value;
  final ValueChanged<Avatar> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = value[part];
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          SizedBox(width: 112, child: Text(part.label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: const TextStyle(fontSize: 16, color: Palette.ink))),
          _Arrow(
            icon: Icons.chevron_left_rounded,
            label: '${part.label}を前へ',
            onTap: () => onChanged(value.withChoice(part, index - 1)),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                value.optionLabel(part),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, color: Palette.ink),
              ),
            ),
          ),
          _Arrow(
            icon: Icons.chevron_right_rounded,
            label: '${part.label}を次へ',
            onTap: () => onChanged(value.withChoice(part, index + 1)),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DoodleIconButton(icon: icon, label: label, onPressed: onTap);
}

/// 顔アイコンと名前を並べた表示。待機画面や登録画面で使う。
class PlayerTag extends StatelessWidget {
  const PlayerTag({super.key, required this.avatar, required this.name, this.trailing, this.iconSize = 44});

  final Avatar avatar;
  final String name;
  final String? trailing;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AvatarIcon(avatar: avatar, size: iconSize),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: name, style: const TextStyle(fontSize: 19)),
              if (trailing != null) TextSpan(text: '  $trailing', style: const TextStyle(fontSize: 15)),
            ]),
            style: const TextStyle(color: Palette.ink, height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// 丸い枠に入った顔アイコン。
class AvatarIcon extends StatelessWidget {
  const AvatarIcon({super.key, required this.avatar, this.size = 44, this.onDark = false});

  final Avatar avatar;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        foregroundPainter: _Ring(onDark: onDark),
        child: ClipOval(child: Padding(padding: EdgeInsets.all(size * 0.06), child: AvatarView(avatar: avatar, size: size, bust: true, onDark: onDark))),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring({required this.onDark});
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawPath(Sketch.circle(c, size.shortestSide / 2 - 1.5, seed: 7, wobble: 0.04), Sketch.pen(2, color: onDark ? Palette.paper : Palette.ink));
  }

  @override
  bool shouldRepaint(covariant _Ring old) => old.onDark != onDark;
}
