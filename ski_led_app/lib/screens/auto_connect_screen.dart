import 'package:flutter/material.dart';

class AutoConnectScreen extends StatelessWidget {
  const AutoConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: Color(0xFF28A745)),
            SizedBox(height: 16),
            Text(
              'Connecting to registered devices...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
