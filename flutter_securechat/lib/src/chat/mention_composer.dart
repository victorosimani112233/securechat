import 'package:flutter/services.dart';

/// Grup mesajinda "@" ile bahsedilebilecek bir uye.
class MentionCandidate {
  const MentionCandidate({required this.userId, required this.label});

  final String userId;
  final String label;
}

/// Imlecin hemen onundeki, henuz tamamlanmamis "@sorgu".
class MentionQuery {
  const MentionQuery({required this.start, required this.text});

  /// "@" isaretinin metindeki konumu.
  final int start;

  /// "@" sonrasindan imlece kadar yazilan kisim (bos olabilir).
  final String text;
}

const _maximumQueryLength = 32;
const _maximumSuggestions = 6;

/// Imlec bir bahsetmenin icindeyse sorguyu dondurur.
///
/// "@" satir basinda ya da bosluktan sonra olmali; e-posta adresi gibi
/// kelime icindeki "@" bahsetme acmaz. Sorgu bosluk icermez: secim
/// yapilmadan bosluk yazilirsa liste kapanir.
MentionQuery? activeMentionQuery(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final cursor = selection.baseOffset;
  final text = value.text;
  if (cursor <= 0 || cursor > text.length) return null;
  final floor = cursor - _maximumQueryLength - 1;
  for (var index = cursor - 1; index >= 0 && index >= floor; index--) {
    final char = text[index];
    if (char == '@') {
      if (index > 0 && !_isSpace(text[index - 1])) return null;
      return MentionQuery(
        start: index,
        text: text.substring(index + 1, cursor),
      );
    }
    if (_isSpace(char)) return null;
  }
  return null;
}

/// Sorguya uyan uyeler: adin kendisi ya da adin herhangi bir kelimesi
/// sorguyla baslamali. Buyuk/kucuk harf ve Turkce I/İ farki yok sayilir.
List<MentionCandidate> filterMentionCandidates(
  Iterable<MentionCandidate> candidates,
  String query,
) {
  final needle = _fold(query);
  final matches = candidates.where((candidate) {
    if (needle.isEmpty) return true;
    final label = _fold(candidate.label);
    return label.startsWith(needle) ||
        label.split(RegExp(r'\s+')).any((word) => word.startsWith(needle));
  }).toList()..sort((a, b) => _fold(a.label).compareTo(_fold(b.label)));
  return matches.take(_maximumSuggestions).toList(growable: false);
}

/// "@sorgu" yerine "@Ad " yazar ve imleci bosluktan sonraya koyar.
TextEditingValue insertMention(
  TextEditingValue value,
  MentionQuery query,
  MentionCandidate candidate,
) {
  final end = query.start + 1 + query.text.length;
  final inserted = '@${candidate.label} ';
  final text = value.text.replaceRange(query.start, end, inserted);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: query.start + inserted.length),
  );
}

/// Gonderilecek metinde hala duran bahsetmelerin kullanici kimlikleri.
///
/// Kullanici secimden sonra "@Ad" kismini sildiyse o kisi bahsedilmis
/// sayilmaz; susturulmus sohbette bile bildirim alacagi icin bu onemli.
List<String> resolveMentionedUserIds(
  String text,
  Map<String, String> pickedLabels,
) => [
  for (final entry in pickedLabels.entries)
    if (text.contains('@${entry.value}')) entry.key,
];

bool _isSpace(String char) => char.trim().isEmpty;

String _fold(String value) => value
    .replaceAll('İ', 'i')
    .replaceAll('I', 'ı')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .trim();

/// Metindeki bahsetmelerin konumlari ("@" dahil).
///
/// "@" satir basinda ya da bosluktan sonra olmali (e-posta adresi
/// bahsetme degil). Ardindan bilinen bir ad geliyorsa (en uzun eslesme,
/// harf buyuklugu farksiz) adin tamami alinir; gonderen kisiyi kendi
/// rehberindeki adla yazmis olabilecegi icin eslesme yoksa "@"tan sonraki
/// ilk kelime alinir. Kelime sonundaki noktalama bahsetmeye dahil edilmez.
List<TextRange> findMentionRanges(String text, Iterable<String> knownLabels) {
  final labels =
      knownLabels
          .map((label) => label.trim())
          .where((label) {
            return label.isNotEmpty;
          })
          .toSet()
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  // Konumlar ozgun metinle ayni kalmali; katlama uzunlugu degistirdiyse
  // (nadir Unicode harfleri) yalniz birebir eslesme denenir.
  final foldedText = _fold(text);
  final folded = foldedText.length == text.length ? foldedText : text;
  final ranges = <TextRange>[];
  var index = 0;
  while (index < text.length) {
    final at = text.indexOf('@', index);
    if (at < 0) break;
    if (at > 0 && !_isSpace(text[at - 1])) {
      index = at + 1;
      continue;
    }
    final start = at + 1;
    var end = -1;
    for (final label in labels) {
      final candidate = _fold(label);
      // Turkce katlama uzunlugu degistirmez; ayni konumlar karsilastirilir.
      if (candidate.length == label.length &&
          folded.startsWith(candidate, start) &&
          (start + label.length == text.length ||
              !_isWordChar(text[start + label.length]))) {
        end = start + label.length;
        break;
      }
    }
    if (end < 0) {
      end = start;
      while (end < text.length && !_isSpace(text[end])) {
        end++;
      }
      while (end > start && _isTrailingPunctuation(text[end - 1])) {
        end--;
      }
    }
    if (end > start) ranges.add(TextRange(start: at, end: end));
    index = end > start ? end : start;
  }
  return ranges;
}

bool _isWordChar(String char) =>
    RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(char);

bool _isTrailingPunctuation(String char) => '.,;:!?)]}\'"'.contains(char);
