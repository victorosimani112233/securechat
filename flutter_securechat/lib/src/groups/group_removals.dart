import '../storage/secure_chat_database.dart';

/// Gruptan cikarilan ya da ayrilan uyelerin yerel kaydi.
///
/// Yoneticiden gelen CREATE uye listesini yerel listeyle birlestirir (kacan
/// ADD_MEMBER'i telafi etmek icin). Cikarmayi henuz islememis bir yonetici
/// her mesajinda eski listeyi gonderdigi icin cikarilan uye herkeste gruba
/// geri ekleniyor ve yeni grup anahtarini aliyordu. Cikarilan uye bu kayitla
/// birlestirmede atlanir; yalniz acik bir ADD_MEMBER kaydi siler.
class GroupRemovals {
  GroupRemovals(this._state);

  final CryptoStateDao _state;

  static String _prefix(String groupId) => 'group-removed:$groupId:';

  Future<void> record(String groupId, String memberId) =>
      _state.put('${_prefix(groupId)}$memberId', '1');

  Future<void> clear(String groupId, String memberId) =>
      _state.delete('${_prefix(groupId)}$memberId');

  Future<Set<String>> removedFrom(String groupId) async {
    final prefix = _prefix(groupId);
    return {
      for (final key in (await _state.getByPrefix(prefix)).keys)
        key.substring(prefix.length),
    };
  }
}
