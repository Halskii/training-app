import 'package:flutter/material.dart';

class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 64),
            const SizedBox(height: 16),
            Text('Your coach is on the way', style: t.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Soon you will be able to chat with your coach here: ask about '
              'your program, report how sessions felt, and flag injuries so '
              'your plan adjusts.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
