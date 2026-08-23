import 'package:flutter/material.dart';

import 'sceptronic_ui.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({
    super.key,
    required this.onFinished,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    _fade = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: 5,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0).chain(
          CurveTween(curve: Curves.easeInCubic),
        ),
        weight: 1,
      ),
    ]).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );

    _controller.forward().whenComplete(widget.onFinished);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SceptronicPalette.background,
      body: SceptronicBackdrop(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Image.asset(
                kSplashLogoAsset,
                width: 320,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
