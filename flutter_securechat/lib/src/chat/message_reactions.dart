import 'dart:convert';
import 'package:characters/characters.dart';

const allowedMessageReactions = {'👍', '🤍', '😂', '😮', '😢', '🙏'};

final _pictograph = RegExp(r'\p{Extended_Pictographic}', unicode: true);
final _flag = RegExp(r'^[\u{1F1E6}-\u{1F1FF}]{2}$', unicode: true);
final _keycap = RegExp(r'^[0-9#*]\uFE0F?\u20E3$', unicode: true);

bool isValidMessageReaction(String value) =>
    value.isNotEmpty &&
    value.length <= 64 &&
    value.characters.length == 1 &&
    (_pictograph.hasMatch(value) ||
        _flag.hasMatch(value) ||
        _keycap.hasMatch(value));

Map<String, Set<String>> parseReactions(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final result = <String, Set<String>>{};
    final seen = <String>{};
    // Legacy records can contain several reactions from one account.
    for (final entry in decoded.entries) {
      if (entry.key is! String ||
          !isValidMessageReaction(entry.key as String) ||
          entry.value is! List)
        continue;
      final voters = (entry.value as List)
          .whereType<String>()
          .where((id) => id.isNotEmpty && seen.add(id))
          .toSet();
      if (voters.isNotEmpty) result[entry.key as String] = voters;
    }
    return result;
  } catch (_) {
    return {};
  }
}

String? applyMessageReaction(
  String? raw,
  String userId,
  String emoji, {
  required bool remove,
}) {
  final reactions = parseReactions(raw);
  for (final entry in reactions.entries) {
    if (!remove || entry.key == emoji) entry.value.remove(userId);
  }
  reactions.removeWhere((_, voters) => voters.isEmpty);
  if (!remove) reactions.putIfAbsent(emoji, () => <String>{}).add(userId);
  return reactions.isEmpty
      ? null
      : jsonEncode({
          for (final entry in reactions.entries)
            entry.key: entry.value.toList(growable: false),
        });
}
