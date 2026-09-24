import 'dart:async';

import '../../core/models.dart';
import '../../services/app_container.dart';
import '../../storage/storage_entities.dart';
import 'recipient_picker_screen.dart';

/// Includes registered contacts without creating empty chats while browsing.
class ConversationRecipients {
  ConversationRecipients(this.container);
  final AppContainer container;
  final _contacts = <String, ContactEntity>{};

  late final Stream<List<RecipientChoice>> choices = Stream.multi((controller) {
    List<Conversation> conversations = [];
    void emit() {
      final peers = conversations
          .where((item) => !item.isGroup)
          .map((item) => item.peerId)
          .toSet();
      controller.add([
        for (final item in conversations)
          RecipientChoice(
            id: item.id,
            name: item.peerName,
            detail: item.peerPhone,
            isGroup: item.isGroup,
          ),
        for (final item in _contacts.values)
          if (!peers.contains(item.id))
            RecipientChoice(
              id: 'contact:${item.id}',
              name: item.displayName,
              detail: item.phoneNumber,
            ),
      ]);
    }

    final chats = container.conversations.watchConversations().listen((items) {
      conversations = items;
      emit();
    }, onError: controller.addError);
    final contacts = container.contacts?.watchRegistered().listen((items) {
      _contacts
        ..clear()
        ..addEntries(items.map((item) => MapEntry(item.id, item)));
      emit();
    }, onError: controller.addError);
    controller.onCancel = () async {
      await chats.cancel();
      await contacts?.cancel();
    };
  });

  Future<List<RecipientChoice>> resolve(List<RecipientChoice> selected) async {
    final result = <RecipientChoice>[];
    for (final item in selected) {
      if (!item.id.startsWith('contact:')) {
        result.add(item);
        continue;
      }
      final contact = _contacts[item.id.substring(8)];
      final service = container.contacts;
      if (contact == null || service == null)
        throw StateError('Contact unavailable');
      final chat = await service.ensureConversation(contact);
      result.add(
        RecipientChoice(
          id: chat.id,
          name: chat.peerName,
          detail: chat.peerPhone,
        ),
      );
    }
    return result;
  }
}
