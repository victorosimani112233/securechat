/// Rehber listesinin alfabetik siralamasi ve harf gruplari.
///
/// Turkce alfabe sirasi kullanilir (C < Ç, G < Ğ, I < İ, O < Ö, S < Ş,
/// U < Ü); Q, W ve X yabanci adlar icin yerlerine alinir. Harfle
/// baslamayan adlar (rakam, simge) en sonda "#" altinda toplanir.
library;

const contactIndexAlphabet = <String>[
  'A', 'B', 'C', 'Ç', 'D', 'E', 'F', 'G', 'Ğ', 'H', 'I', 'İ', 'J', 'K', //
  'L', 'M', 'N', 'O', 'Ö', 'P', 'Q', 'R', 'S', 'Ş', 'T', 'U', 'Ü', 'V', //
  'W', 'X', 'Y', 'Z',
];

/// Harfle baslamayan adlarin grubu.
const contactIndexOther = '#';

final _rank = {
  for (var i = 0; i < contactIndexAlphabet.length; i++)
    contactIndexAlphabet[i]: i,
};

/// Turkcede i/ı buyuk harfe dogru cevrilir (i -> İ, ı -> I).
String _upper(String value) =>
    value.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Aksanli Latin harfleri en yakin harfin grubuna duser (Â -> A).
const _folded = {
  'Â': 'A', 'À': 'A', 'Á': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A', //
  'Ê': 'E', 'È': 'E', 'É': 'E', 'Ë': 'E', //
  'Î': 'İ', 'Ì': 'İ', 'Í': 'İ', 'Ï': 'İ', //
  'Ô': 'O', 'Ò': 'O', 'Ó': 'O', 'Õ': 'O', //
  'Û': 'U', 'Ù': 'U', 'Ú': 'U', //
  'Ñ': 'N',
};

String _letterOf(String character) {
  final upper = _upper(character);
  return _folded[upper] ?? upper;
}

/// Adin listede altinda gosterilecegi harf.
String contactIndexLetter(String name) {
  // Karsi tarafin kendi verdigi ad "~Ad" bicimindedir; "~" sayilmaz.
  final trimmed = name.trim().replaceFirst(RegExp(r'^~\s*'), '');
  if (trimmed.isEmpty) return contactIndexOther;
  final letter = _letterOf(String.fromCharCode(trimmed.runes.first));
  return _rank.containsKey(letter) ? letter : contactIndexOther;
}

List<int> _sortKey(String name) {
  final trimmed = name.trim().replaceFirst(RegExp(r'^~\s*'), '');
  final key = <int>[
    // Harfle baslamayanlar sona.
    contactIndexLetter(name) == contactIndexOther ? 1 : 0,
  ];
  for (final rune in trimmed.runes) {
    final letter = _letterOf(String.fromCharCode(rune));
    final rank = _rank[letter];
    // Alfabe disi karakterler (rakam, bosluk, simge) harflerden sonra kendi
    // kod sirasiyla.
    key.add(rank ?? 1000 + rune);
  }
  return key;
}

int _compareKeys(List<int> left, List<int> right) {
  final length = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final diff = left[i] - right[i];
    if (diff != 0) return diff;
  }
  return left.length - right.length;
}

/// Adlari Turkce alfabe sirasiyla karsilastirir.
int compareContactNames(String left, String right) {
  final order = _compareKeys(_sortKey(left), _sortKey(right));
  return order != 0 ? order : left.compareTo(right);
}

/// Ogeleri alfabetik siralar ve harf gruplarina ayirir; "#" grubu sondadir.
List<({String letter, List<T> items})> groupContactsByLetter<T>(
  Iterable<T> items,
  String Function(T item) nameOf,
) {
  final keyed = [for (final item in items) (item, _sortKey(nameOf(item)))];
  keyed.sort((left, right) {
    final order = _compareKeys(left.$2, right.$2);
    return order != 0 ? order : nameOf(left.$1).compareTo(nameOf(right.$1));
  });
  final groups = <({String letter, List<T> items})>[];
  for (final (item, _) in keyed) {
    final letter = contactIndexLetter(nameOf(item));
    if (groups.isEmpty || groups.last.letter != letter) {
      groups.add((letter: letter, items: <T>[]));
    }
    groups.last.items.add(item);
  }
  return groups;
}
