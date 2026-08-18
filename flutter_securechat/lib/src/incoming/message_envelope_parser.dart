import '../storage/storage_entities.dart';

class ParsedMessageEnvelope {
  const ParsedMessageEnvelope({
    required this.content,
    this.messageId,
    this.replyToId,
    this.contentType = StorageMessageContentType.text,
    this.pollVote,
    this.absoluteExpiresAt,
    this.isViewOnce = false,
    this.mentionedUserIds = const [],
  });

  final String? messageId;
  final String? replyToId;
  final String content;
  final StorageMessageContentType contentType;
  final PollVoteReference? pollVote;
  final int? absoluteExpiresAt;
  final bool isViewOnce;
  final List<String> mentionedUserIds;
}

class PollVoteReference {
  const PollVoteReference(this.pollMessageId, this.optionIndex);
  final String pollMessageId;
  final int optionIndex;
}

ParsedMessageEnvelope parseMessageEnvelope(String content) {
  var remaining = content;
  String? messageId;
  String? replyToId;
  int? absoluteExpiresAt;
  var isViewOnce = false;
  var mentionedUserIds = const <String>[];

  (String?, String) consumeValue(String input, String prefix) {
    if (!input.startsWith(prefix)) return (null, input);
    final separator = input.indexOf(':', prefix.length);
    if (separator < 0) return (null, input);
    return (
      input.substring(prefix.length, separator),
      input.substring(separator + 1),
    );
  }

  final message = consumeValue(remaining, 'MSGID:');
  messageId = message.$1;
  remaining = message.$2;
  final reply = consumeValue(remaining, 'REPLY:');
  replyToId = reply.$1;
  remaining = reply.$2;
  final expiry = consumeValue(remaining, 'EXP:');
  absoluteExpiresAt = int.tryParse(expiry.$1 ?? '');
  remaining = expiry.$2;
  if (remaining.startsWith('VIEWONCE:')) {
    isViewOnce = true;
    remaining = remaining.substring('VIEWONCE:'.length);
  }
  final mention = consumeValue(remaining, 'MENTION:');
  if (mention.$1 != null) {
    mentionedUserIds = mention.$1!
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    remaining = mention.$2;
  }
  if (remaining.startsWith('POLLVOTE:')) {
    final parts = remaining.substring('POLLVOTE:'.length).split(':');
    final option = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (parts.isNotEmpty && option != null) {
      return ParsedMessageEnvelope(
        messageId: messageId,
        content: '',
        pollVote: PollVoteReference(parts.first, option),
        absoluteExpiresAt: absoluteExpiresAt,
        isViewOnce: isViewOnce,
        mentionedUserIds: mentionedUserIds,
      );
    }
  }
  final isPoll = remaining.startsWith('POLL:');
  if (isPoll) remaining = remaining.substring('POLL:'.length);
  return ParsedMessageEnvelope(
    messageId: messageId,
    replyToId: replyToId,
    content: remaining,
    contentType: isPoll
        ? StorageMessageContentType.poll
        : StorageMessageContentType.text,
    absoluteExpiresAt: absoluteExpiresAt,
    isViewOnce: isViewOnce,
    mentionedUserIds: mentionedUserIds,
  );
}
