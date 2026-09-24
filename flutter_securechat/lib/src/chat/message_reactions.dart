import 'dart:convert';

const allowedMessageReactions = {'👍', '❤️', '😂', '😮', '😢', '🙏'};

Map<String, Set<String>> parseReactions(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final result = <String, Set<String>>{};
    final seen = <String>{};
    // Legacy records can contain several reactions from one account.
    for (final entry in decoded.entries) {
      if (!allowedMessageReactions.contains(entry.key) || entry.value is! List)
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
