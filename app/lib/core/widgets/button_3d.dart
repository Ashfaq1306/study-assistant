import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A chunky button with a visible bottom edge that sinks when pressed,
/// like a real key. The signature control of the app.
class Button3D extends StatefulWidget {
  const Button3D({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.violet,
    this.edgeColor = AppColors.violetDeep,
    this.foreground = Colors.white,
    this.loading = false,
    this.height = 58,
  });

  /// White face with a soft edge, for secondary actions.
  const Button3D.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.height = 58,
  }) : color = AppColors.card,
       edgeColor = AppColors.line,
       foreground = AppColors.violet;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color edgeColor;
  final Color foreground;
  final bool loading;
  final double height;

  @override
  State<Button3D> createState() => _Button3DState();
}

class _Button3DState extends State<Button3D> {
  static const _depth = 6.0;
  static const _radius = 20.0;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _setPressed(bool value) {
    if (_enabled && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final face = _enabled ? widget.color : Color.lerp(widget.color, AppColors.line, 0.55)!;
    final edge = _enabled ? widget.edgeColor : AppColors.line;
    final offset = _pressed ? _depth : 0.0;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: _enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: SizedBox(
          height: widget.height + _depth,
          child: Stack(
            children: [
              Positioned.fill(
                top: _depth,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: edge, borderRadius: BorderRadius.circular(_radius)),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 70),
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: offset,
                height: widget.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_radius),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(face, Colors.white, 0.12)!, face],
                    ),
                    border: widget.color == AppColors.card ? Border.all(color: AppColors.line, width: 1.5) : null,
                  ),
                  child: Center(child: _content(_enabled ? widget.foreground : AppColors.inkFaint)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(Color color) {
    if (widget.loading) {
      return SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 3, color: color));
    }
    final label = Text(
      widget.label,
      style: TextStyle(fontFamily: 'Nunito', fontSize: 17, fontWeight: FontWeight.w900, color: color),
    );
    if (widget.icon == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(widget.icon, color: color, size: 22),
        const SizedBox(width: 10),
        label,
      ],
    );
  }
}
