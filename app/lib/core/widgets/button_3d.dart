import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A chunky, glossy button with a physical bottom edge that sinks when pressed.
/// Colours default to the current theme's accent.
class Button3D extends StatefulWidget {
  const Button3D({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.edgeColor,
    this.foreground,
    this.loading = false,
    this.height = 58,
  }) : _secondary = false;

  /// A frosted face with a soft edge, for secondary actions.
  const Button3D.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.height = 58,
  }) : color = null,
       edgeColor = null,
       foreground = null,
       _secondary = true;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Face colour; the theme accent when null.
  final Color? color;

  /// Bottom edge; a deeper shade of the face when null.
  final Color? edgeColor;
  final Color? foreground;
  final bool loading;
  final double height;
  final bool _secondary;

  @override
  State<Button3D> createState() => _Button3DState();
}

/// A darker shade of [color], for the 3D edge.
Color deeper(Color color, [double amount = 0.16]) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
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
    final secondary = widget._secondary;
    final base = widget.color ?? (secondary ? AppColors.card : AppColors.hero);
    final face = _enabled ? base : Color.lerp(base, AppColors.line, 0.55)!;
    final edge = !_enabled
        ? AppColors.line
        : secondary
        ? AppColors.line
        : (AppColors.isDark ? deeper(face, 0.2) : (widget.edgeColor ?? deeper(face)));
    final foreground = !_enabled
        ? AppColors.inkFaint
        : widget.foreground ?? (secondary ? AppColors.violet : Colors.white);
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
                      colors: [Color.lerp(face, Colors.white, secondary ? 0.0 : 0.12)!, face],
                    ),
                    border: secondary
                        ? Border.all(color: AppColors.isDark ? AppColors.glassEdge : AppColors.line, width: 1.5)
                        : null,
                  ),
                  child: Center(child: _content(foreground)),
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
    final label = Flexible(
      child: Text(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontFamily: 'Nunito', fontSize: 17, fontWeight: FontWeight.w900, color: color),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[Icon(widget.icon, color: color, size: 22), const SizedBox(width: 10)],
          label,
        ],
      ),
    );
  }
}
