import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../storage/secure_chat_database.dart';

/// Toplu mesaj icin kaydedilmis alici listesi.
///
/// Liste yalniz bu cihazda, sifreli veritabaninda durur; sunucu ne listeyi ne
/// de kimlerin ayni listede oldugunu gorur. Uyeler alici secicisindeki
/// kimliklerdir (sohbet kimligi ya da `contact:` ile baslayan rehber kaydi).
class BroadcastList {
  const BroadcastList({
    required this.id,
    required this.name,
    required this.memberIds,
  });

  final String id;
  final String name;
  final List<String> memberIds;

  static BroadcastList? tryParse(String id, String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final name = json['name'];
      final members = json['members'];
      if (name is! String || members is! List) return null;
      return BroadcastList(
        id: id,
        name: name,
        memberIds: members.whereType<String>().toList(growable: false),
      );
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode({'name': name, 'members': memberIds});
}

class BroadcastListException implements Exception {
  const BroadcastListException(this.reason);
  final BroadcastListError reason;
}

enum BroadcastListError { emptyName, noMembers, tooManyMembers, tooManyLists }

abstract interface class BroadcastListStore {
  Stream<List<BroadcastList>> watch();

  /// Ayni adda (buyuk/kucuk harf farksiz) liste varsa onu gunceller.
  Future<BroadcastList> save(String name, Iterable<String> memberIds);

  Future<void> delete(String id);
}

const maxBroadcastLists = 50;
const maxBroadcastListMembers = 256;
const maxBroadcastListNameLength = 60;

/// Kayit oncesi dogrulama; temizlenmis ad ve uyeleri dondurur.
(String, List<String>) validateBroadcastList(
  String name,
  Iterable<String> memberIds,
) {
  final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.isEmpty) {
    throw const BroadcastListException(BroadcastListError.emptyName);
  }
  final members = memberIds.where((id) => id.isNotEmpty).toSet().toList();
  if (members.isEmpty) {
    throw const BroadcastListException(BroadcastListError.noMembers);
  }
  if (members.length > maxBroadcastListMembers) {
    throw const BroadcastListException(BroadcastListError.tooManyMembers);
  }
  return (
    clean.length > maxBroadcastListNameLength
        ? clean.substring(0, maxBroadcastListNameLength)
        : clean,
    members,
  );
}

List<BroadcastList> _sorted(Iterable<BroadcastList> lists) =>
    lists.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

String _newId() {
  final random = Random.secure();
  return List.generate(
    12,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class StorageBroadcastListStore implements BroadcastListStore {
  StorageBroadcastListStore(this._database);

  static const _prefix = 'broadcast-list:';
  final SecureChatDatabase _database;

  @override
  Stream<List<BroadcastList>> watch() => _database.cryptoState
      .watchByPrefix(_prefix)
      .map(
        (entries) => _sorted([
          for (final entry in entries.entries)
            ?BroadcastList.tryParse(
              entry.key.substring(_prefix.length),
              entry.value,
            ),
        ]),
      );

  @override
  Future<BroadcastList> save(String name, Iterable<String> memberIds) async {
    final (clean, members) = validateBroadcastList(name, memberIds);
    final existing = await watch().first;
    final match = existing
        .where((list) => list.name.toLowerCase() == clean.toLowerCase())
        .firstOrNull;
    if (match == null && existing.length >= maxBroadcastLists) {
      throw const BroadcastListException(BroadcastListError.tooManyLists);
    }
    final list = BroadcastList(
      id: match?.id ?? _newId(),
      name: clean,
      memberIds: members,
    );
    await _database.cryptoState.put('$_prefix${list.id}', list.encode());
    return list;
  }

  @override
  Future<void> delete(String id) => _database.cryptoState.delete('$_prefix$id');
}

/// Testler ve veritabanisiz kabuk icin.
class InMemoryBroadcastListStore implements BroadcastListStore {
  final _lists = <String, BroadcastList>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<BroadcastList>> watch() async* {
    yield _sorted(_lists.values);
    yield* _changes.stream.map((_) => _sorted(_lists.values));
  }

  @override
  Future<BroadcastList> save(String name, Iterable<String> memberIds) async {
    final (clean, members) = validateBroadcastList(name, memberIds);
    final match = _lists.values
        .where((list) => list.name.toLowerCase() == clean.toLowerCase())
        .firstOrNull;
    if (match == null && _lists.length >= maxBroadcastLists) {
      throw const BroadcastListException(BroadcastListError.tooManyLists);
    }
    final list = BroadcastList(
      id: match?.id ?? _newId(),
      name: clean,
      memberIds: members,
    );
    _lists[list.id] = list;
    _changes.add(null);
    return list;
  }

  @override
  Future<void> delete(String id) async {
    if (_lists.remove(id) != null) _changes.add(null);
  }
}
