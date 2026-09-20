import 'package:flutter/material.dart';

class GeneratedAvatar extends StatelessWidget {
  const GeneratedAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.isGroup = false,
  });

  final String name;
  final double size;

  /// Grup sohbetleri kisi sohbetlerinden ayirt edilebilmeli. Ayni monogram
  /// her ikisinde de kullanilinca kullanici yanlis sohbete girebiliyordu.
  final bool isGroup;

  /// Ad parcalarini ayiran karakterler.
  ///
  /// Yalnizca bosluktan bolunuyordu; bu yuzden "QA_Test_Mehmet",
  /// "QA_Grup_1" ve "qa-peer-01" ayni tek harfe ("Q") dusuyor, sohbet
  /// listesinde birbirinden ayirt edilemiyordu. Alt cizgi, tire ve nokta da
  /// gunluk kullanimda ad ayiricisidir.
  static final _separators = RegExp(r'[\s._\-]+');

  /// Bas harfleri uretir. Harf/rakam olmayan parcalar atlanir; boylece
  /// "+90 532 ..." gibi degerler anlamsiz isaret yerine rakam gosterir.
  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(_separators)
        .where((part) => part.isNotEmpty)
        .where((part) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(part))
        .toList();
    if (parts.isEmpty) return '';
    final letters = parts
        .take(2)
        .map(
          (part) => part.characters
              .firstWhere(
                (character) =>
                    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(character),
                orElse: () => part.characters.first,
              )
              .toUpperCase(),
        )
        .join();
    return letters;
  }

  @override
  Widget build(BuildContext context) {
    final colors = [
      Theme.of(context).colorScheme.primary,
      const Color(0xFF6B737D),
      const Color(0xFF22C55E),
      const Color(0xFFFFB800),
    ];
    final color = colors[name.hashCode.abs() % colors.length];
    final initials = initialsOf(name);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: isGroup
          ? Icon(Icons.groups, color: Colors.white, size: size * .55)
          : Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * .34,
              ),
            ),
    );
  }
}
