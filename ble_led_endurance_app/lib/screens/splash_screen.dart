import 'package:flutter/material.dart';

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
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _fade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      _controller.forward().then((_) {
        widget.onFinished();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Image.asset(
              'assets/E7E1C2ED_logo.png',
              width: 220,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 240,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'FAE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
