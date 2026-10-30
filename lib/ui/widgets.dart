import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../app/feedback.dart';
import 'doodle.dart';

/// 紙の背景と戻るボタンを持つ共通の画面枠。
class DoodleScaffold extends StatelessWidget {
  const DoodleScaffold({super.key, required this.child, this.title, this.showBack = true, this.onBack, this.leading, this.actions});

  final Widget child;
  final String? title;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: PaperBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBack || title != null || leading != null || actions != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
                  child: Row(
                    children: [
                      if (showBack)
                        DoodleIconButton(
                          icon: Icons.arrow_back_rounded,
                          label: 'もどる',
                          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                        ),
                      ?leading,
                      const SizedBox(width: 6),
                      if (title != null)
                        Expanded(
                          child: Text(title!, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                        )
                      else
                        const Spacer(),
                      ...?actions,
                    ],
                  ),
                ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 手描きの枠のボタン。押すと少し沈む。
class DoodleButton extends StatefulWidget {
  const DoodleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.seed = 1,
    this.fontSize = 22,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final int seed;
  final double fontSize;

  @override
  State<DoodleButton> createState() => _DoodleButtonState();
}

class _DoodleButtonState extends State<DoodleButton> {
  bool _down = false;
  bool _focused = false;
  bool _hovered = false;

  void _activate() {
    if (widget.onPressed == null) return;
    Services.of(context).feedback.play(Sound.tap);
    HapticFeedback.selectionClick();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final fg = widget.primary && enabled ? Palette.paper : (enabled ? Palette.ink : Palette.pencil);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) { _activate(); return null; }),
        },
        child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled ? _activate : null,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 60),
          offset: _down ? const Offset(0.006, 0.04) : Offset.zero,
          child: CustomPaint(
            painter: SketchBorderPainter(
              seed: widget.seed,
              fillColor: widget.primary && enabled ? Palette.ink : Palette.paper,
              shadow: enabled && !_down && !_hovered,
              strokeWidth: _focused ? 4 : 2.6,
              dashed: !enabled,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 22, 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: fg, size: widget.fontSize + 4),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: kFontFamily, fontSize: widget.fontSize, color: fg, height: 1.15),
                          ),
                          if (widget.subtitle != null)
                            Text(
                              widget.subtitle!,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: kFontFamily, fontSize: 14, color: fg, height: 1.2),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class DoodleIconButton extends StatelessWidget {
  const DoodleIconButton({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onPressed,
          radius: 28,
          child: SizedBox(
            width: 52,
            height: 52,
            child: CustomPaint(
              painter: _CircleSketch(),
              child: Icon(icon, color: Palette.ink, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleSketch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    canvas.drawPath(Sketch.circle(c, r, seed: 9), Sketch.fill(Palette.paper));
    canvas.drawPath(Sketch.circle(c, r, seed: 9), Sketch.pen(2.2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 手描きの枠で囲んだ箱。
class DoodleBox extends StatelessWidget {
  const DoodleBox({super.key, required this.child, this.seed = 2, this.padding = const EdgeInsets.all(16), this.dashed = false, this.shadow = false});

  final Widget child;
  final int seed;
  final EdgeInsets padding;
  final bool dashed;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SketchBorderPainter(seed: seed, shadow: shadow, dashed: dashed, strokeWidth: 2.2),
      child: Padding(padding: padding + const EdgeInsets.only(right: 4, bottom: 4), child: child),
    );
  }
}

/// 手描きの下線つき見出し。
class DoodleHeading extends StatelessWidget {
  const DoodleHeading(this.text, {super.key, this.size = 22});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _UnderlinePainter(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(fontFamily: kFontFamily, fontSize: size, color: Palette.ink)),
      ),
    );
  }
}

class _UnderlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Sketch.line(Offset(0, size.height - 2), Offset(size.width, size.height - 3), seed: size.width.toInt(), wobble: 1.2),
      Sketch.pen(2.2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 接続状態の表示。色ではなく記号の形(●/○/×)と文字で区別する。
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.state, required this.text});

  final StatusKind state;
  final String text;

  @override
  Widget build(BuildContext context) {
    final mark = switch (state) {
      StatusKind.ok => '●',
      StatusKind.waiting => '○',
      StatusKind.bad => '×',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 26, child: Text(mark, style: const TextStyle(fontSize: 18, color: Palette.ink))),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 17, color: Palette.ink, height: 1.35))),
      ],
    );
  }
}

enum StatusKind { ok, waiting, bad }

/// 回る鉛筆の丸(待機中の表示)。省電力のため控えめに動かす。
class DoodleSpinner extends StatefulWidget {
  const DoodleSpinner({super.key, this.size = 28});
  final double size;

  @override
  State<DoodleSpinner> createState() => _DoodleSpinnerState();
}

class _DoodleSpinnerState extends State<DoodleSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: SizedBox.square(dimension: widget.size, child: CustomPaint(painter: _ArcSketch())),
    );
  }
}

class _ArcSketch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawArc(r.deflate(3), 0, 4.6, false, Sketch.pen(3));
    canvas.drawArc(r.deflate(5), 0.3, 4.0, false, Sketch.pen(1.4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 手描き風の確認ダイアログ。
Future<bool> confirmDialog(BuildContext context, {required String message, required String ok, String cancel = 'やめる'}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: DoodleBox(
        shadow: true,
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: const TextStyle(fontSize: 20, color: Palette.ink, height: 1.4)),
            const SizedBox(height: 20),
            DoodleButton(label: ok, primary: true, onPressed: () => Navigator.pop(ctx, true), seed: 5),
            const SizedBox(height: 12),
            DoodleButton(label: cancel, onPressed: () => Navigator.pop(ctx, false), seed: 6),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// 手描きのタブ。選んだタブは黒くぬる（スマホ版 DoodleTabs）。
/// PC ではマウスのカーソルと、Tab キーでのフォーカス・Enter / Space での切り替えにも対応する。
class DoodleTabs extends StatelessWidget {
  const DoodleTabs({super.key, required this.labels, required this.selected, required this.onChanged, this.seed = 70});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final int seed;

  @override
  Widget build(BuildContext context) {
    // スクロールする画面の中でも、タブの高さをいちばん高いものにそろえる
    // （stretch だけだと高さの上限がなく、レイアウトが壊れる）
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, label) in labels.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _DoodleTab(label: label, active: i == selected, seed: seed + i, onTap: () => onChanged(i))),
          ],
        ],
      ),
    );
  }
}

class _DoodleTab extends StatefulWidget {
  const _DoodleTab({required this.label, required this.active, required this.seed, required this.onTap});

  final String label;
  final bool active;
  final int seed;
  final VoidCallback onTap;

  @override
  State<_DoodleTab> createState() => _DoodleTabState();
}

class _DoodleTabState extends State<_DoodleTab> {
  bool _focused = false;

  void _activate() {
    if (widget.active) return;
    Services.of(context).feedback.play(Sound.tap);
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final fg = active ? Palette.paper : Palette.ink;
    return Semantics(
      button: true,
      selected: active,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: active ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _activate();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: active ? null : _activate,
          child: CustomPaint(
            painter: SketchBorderPainter(
              seed: widget.seed,
              fillColor: active ? Palette.ink : Palette.paper,
              shadow: false,
              dashed: !active,
              strokeWidth: _focused ? 3.6 : 2.2,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 11),
                  child: Text(widget.label, textAlign: TextAlign.center, style: TextStyle(fontFamily: kFontFamily, fontSize: 18, color: fg, height: 1.15)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
