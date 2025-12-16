import 'package:flutter/widgets.dart';

/// A simple on-appear fade, useful to give pages a gentle entrance.
///
/// It plays once when the widget is first inserted. For AnimatedSwitcher page
/// transitions, this stacks nicely with slide transitions.
class AppearFade extends StatefulWidget {
  const AppearFade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 700),
    this.curve = Curves.easeOutCubic,
  });
  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  State<AppearFade> createState() => _AppearFadeState();
}

class _AppearFadeState extends State<AppearFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: widget.curve);
    // Start after first frame so layout is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: widget.child);
}
