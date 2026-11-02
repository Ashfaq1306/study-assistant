import 'package:flutter/material.dart';

/// Fades and slides its child up into place after [delay]; for staggered entrances.
/// Appears at once when the phone asks for reduced motion.
class FloatIn extends StatefulWidget {
  const FloatIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 24});

  final Widget child;
  final Duration delay;

  /// How far below its place the child starts, in pixels.
  final double offset;

  @override
  State<FloatIn> createState() => _FloatInState();
}

class _FloatInState extends State<FloatIn> with SingleTickerProviderStateMixin {
  static const _move = Duration(milliseconds: 650);

  // The delay is part of the animation (no timers left behind if the screen closes early).
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.delay + _move);
  late final double _start = widget.delay.inMicroseconds / (widget.delay + _move).inMicroseconds;
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Interval(_start, 1));
  late final Animation<double> _rise = CurvedAnimation(
    parent: _controller,
    curve: Interval(_start, 1, curve: Curves.easeOutBack),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Opacity(
      opacity: _fade.value.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, (1 - _rise.value) * widget.offset), child: child),
    ),
    child: widget.child,
  );
}
