import 'package:flutter/material.dart';

class GeneratedAvatar extends StatelessWidget {
  const GeneratedAvatar({super.key, required this.name, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = [
      Theme.of(context).colorScheme.primary,
      const Color(0xFF6B737D),
      const Color(0xFF22C55E),
      const Color(0xFFFFB800),
    ];
    final color = colors[name.hashCode.abs() % colors.length];
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
