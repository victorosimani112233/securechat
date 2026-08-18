import 'dart:convert';
import 'dart:math';

import '../core/signal_message.dart';
import '../domain/send_message_use_case.dart';
import '../groups/private_group_route.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';

class PollData {
  PollData({
    required this.question,
    required List<String> options,
    required this.singleChoice,
    Map<int, List<String>> votes = const {},
  }) : options = List.unmodifiable(options),
       votes = {
         for (final entry in votes.entries)
           entry.key: List.unmodifiable(entry.value.toSet()),
       } {
    if (question.trim().isEmpty || question.trim().length > 500) {
      throw const FormatException('Anket sorusu 1-500 karakter olmalıdır.');
    }
    if (this.options.length < 2 || this.options.length > 4) {
      throw const FormatException('Anket 2-4 seçenek içermelidir.');
    }
    if (this.options.any(
      (option) => option.trim().isEmpty || option.length > 200,
    )) {
      throw const FormatException(
        'Anket seçenekleri 1-200 karakter olmalıdır.',
      );
    }
  }

  final String question;
  final List<String> options;
  final bool singleChoice;
  final Map<int, List<String>> votes;

  factory PollData.parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Geçersiz anket verisi');
    final json = decoded.cast<String, Object?>();
    final options =
        (json['options'] as List?)
            ?.whereType<String>()
            .map((value) => value.trim())
            .toList(growable: false) ??
        const <String>[];
    final votes = <int, List<String>>{};
    final rawVotes = json['votes'];
    if (rawVotes is Map) {
      for (final entry in rawVotes.entries) {
        final index = int.tryParse(entry.key.toString());
        if (index == null || index < 0 || index >= options.length) continue;
        final value = entry.value;
        if (value is List) {
          votes[index] = value
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList(growable: false);
        }
      }
    }
    return PollData(
      question: json['question'] as String? ?? '',
      options: options,
      singleChoice: json['singleChoice'] as bool? ?? true,
      votes: votes,
    );
  }

  PollData toggleVote(String userId, int optionIndex) {
    if (userId.isEmpty || optionIndex < 0 || optionIndex >= options.length) {
      throw const FormatException('Geçersiz anket oyu');
    }
    final mutable = {
      for (final entry in votes.entries) entry.key: entry.value.toSet(),
    };
    final wasSelected = mutable[optionIndex]?.contains(userId) ?? false;
    if (singleChoice) {
      for (final voters in mutable.values) {
        voters.remove(userId);
      }
    }
    final selected = mutable.putIfAbsent(optionIndex, () => <String>{});
    if (!wasSelected) selected.add(userId);
    return PollData(
      question: question,
      options: options,
      singleChoice: singleChoice,
      votes: {
        for (final entry in mutable.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.toList(),
      },
    );
  }

  int get totalVotes =>
      votes.values.fold(0, (sum, value) => sum + value.length);

  String encode() => jsonEncode({
    'question': question.trim(),
    'options': options.map((option) => option.trim()).toList(),
    'singleChoice': singleChoice,
    'votes': {for (final entry in votes.entries) '${entry.key}': entry.value},
  });
}

class PollService {
  PollService({
    required SecureChatDatabase database,
    required SendMessageUseCase sender,
    required SignalingService signaling,
    required SessionStore session,
    required CryptoService crypto,
    Random? random,
  }) : _database = database,
       _sender = sender,
       _signaling = signaling,
       _session = session,
       _crypto = crypto,
       _random = random ?? Random.secure();

  final SecureChatDatabase _database;
  final SendMessageUseCase _sender;
  final SignalingService _signaling;
  final SessionStore _session;
  final CryptoService _crypto;
  final Random _random;

  Future<SendMessageOutcome> create(String conversationId, PollData poll) =>
      _sender(
        SendMessageRequest(
          conversationId: conversationId,
          content: poll.encode(),
          contentType: StorageMessageContentType.poll,
        ),
      );

  Future<bool> vote(String pollMessageId, int optionIndex) async {
    final userId = _session.userId;
    if (userId == null || userId.isEmpty) return false;
    final message = await _database.messages.getById(pollMessageId);
    if (message == null ||
        message.contentType != StorageMessageContentType.poll) {
      return false;
    }
    final poll = PollData.parse(message.content);
    final updated = poll.toggleVote(userId, optionIndex);
    final conversation = await _database.conversations.getById(
      message.conversationId,
    );
    if (conversation == null) return false;
    final plaintext = 'MSGID:${_newId()}:POLLVOTE:$pollMessageId:$optionIndex';
    late final List<SignalMessage> signals;
    try {
      if (conversation.isGroup) {
        final encrypted = await _crypto.encryptGroup(
          senderId: userId,
          groupId: conversation.id,
          plaintext: plaintext,
        );
        final route = encodePrivateGroupRoute(
          groupId: conversation.id,
          groupEnvelope: encrypted,
        );
        signals = [];
        for (final member in _members(
          conversation.groupMembers,
        ).where((id) => id != userId)) {
          signals.add(
            EncryptedSignalMessage(
              senderId: userId,
              recipientId: member,
              timestamp: DateTime.now(),
              envelope: await _crypto.encryptDirect(
                recipientId: member,
                plaintext: route,
              ),
            ),
          );
        }
        if (signals.isEmpty) return false;
      } else {
        signals = [
          EncryptedSignalMessage(
            senderId: userId,
            recipientId: conversation.peerId,
            timestamp: DateTime.now(),
            envelope: await _crypto.encryptDirect(
              recipientId: conversation.peerId,
              plaintext: plaintext,
            ),
          ),
        ];
      }
    } catch (_) {
      return false;
    }
    await _database.messages.updateContent(
      pollMessageId,
      updated.encode(),
      StorageMessageContentType.poll,
    );
    await _signaling.ensureConnected(timeout: const Duration(seconds: 8));
    for (var attempt = 0; attempt < 3; attempt++) {
      var allSent = true;
      for (final signal in signals) {
        if (!await _signaling.send(signal)) allSent = false;
      }
      if (allSent) return true;
    }
    await _database.messages.updateContent(
      pollMessageId,
      poll.encode(),
      StorageMessageContentType.poll,
    );
    return false;
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${List.generate(12, (_) => _random.nextInt(16).toRadixString(16)).join()}';
}

List<String> _members(String? csv) => csv == null
    ? const []
    : csv
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
