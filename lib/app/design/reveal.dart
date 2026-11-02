import 'package:flutter/material.dart';

import 'tokens.dart';

/// Fades and slides its child up once, [index] * 45 ms after the page shows,
/// so a grid of cards settles in a soft cascade. Uses a single controller (no
/// timers) and is skipped entirely when the platform asks for reduced motion.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _step = 45;
  static const _maxDelayed = 8;

  late final AnimationController _controller;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    final delay = _step * widget.index.clamp(0, _maxDelayed);
    final total = delay + Motion.slow.inMilliseconds;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    _t = CurvedAnimation(
      parent: _controller,
      curve: Interval(delay / total, 1, curve: Motion.curve),
    );
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - _t.value)), child: child),
      ),
    );
  }
}
