import 'dart:io';

import '../core/models.dart';
import '../domain/send_message_use_case.dart';
import '../media/file_transfer_manager.dart';
import '../media/media_attachment.dart';
import '../media/media_message_service.dart';
import '../media/voice_note_service.dart';
import 'poll_service.dart';

enum ForwardMessageOutcome {
  sent,
  notAllowed,
  sourceUnavailable,
  encryptionFailed,
  deliveryFailed,
}

class MessageForwardingService {
  const MessageForwardingService({
    required SendMessageUseCase sender,
    required PollService polls,
    required MediaMessageService media,
  }) : _sender = sender,
       _polls = polls,
       _media = media;

  final SendMessageUseCase _sender;
  final PollService _polls;
  final MediaMessageService _media;

  Future<List<ForwardMessageOutcome>> forwardAll({
    required Iterable<LocalMessage> sources,
    required Conversation target,
  }) async {
    final outcomes = <ForwardMessageOutcome>[];
    for (final source in sources) {
      outcomes.add(await forward(source: source, target: target));
    }
    return List.unmodifiable(outcomes);
  }

  Future<ForwardMessageOutcome> forward({
    required LocalMessage source,
    required Conversation target,
  }) async {
    if (source.isViewOnce ||
        source.isDeleted ||
        source.contentType == MessageContentType.system ||
        target.isReadOnly) {
      return ForwardMessageOutcome.notAllowed;
    }

    return switch (source.contentType) {
      MessageContentType.text => _forwardText(source.content, target.id),
      MessageContentType.poll => _forwardPoll(source.content, target.id),
      MessageContentType.image ||
      MessageContentType.file ||
      MessageContentType.voiceNote => _forwardMedia(source, target),
      MessageContentType.system || MessageContentType.deleted => Future.value(
        ForwardMessageOutcome.notAllowed,
      ),
    };
  }

  Future<ForwardMessageOutcome> _forwardText(
    String content,
    String targetConversationId,
  ) async => _mapSendOutcome(
    await _sender(
      SendMessageRequest(
        conversationId: targetConversationId,
        content: content,
      ),
    ),
  );

  Future<ForwardMessageOutcome> _forwardPoll(
    String content,
    String targetConversationId,
  ) async {
    try {
      final source = PollData.parse(content);
      final freshPoll = PollData(
        question: source.question,
        options: source.options,
        singleChoice: source.singleChoice,
      );
      return _mapSendOutcome(
        await _polls.create(targetConversationId, freshPoll),
      );
    } on FormatException {
      return ForwardMessageOutcome.sourceUnavailable;
    }
  }

  Future<ForwardMessageOutcome> _forwardMedia(
    LocalMessage source,
    Conversation target,
  ) async {
    final path = source.filePath;
    final fileName = source.fileName;
    final mimeType = source.fileMimeType;
    if (path == null ||
        path.isEmpty ||
        fileName == null ||
        fileName.isEmpty ||
        mimeType == null ||
        mimeType.isEmpty ||
        !await File(path).exists()) {
      return ForwardMessageOutcome.sourceUnavailable;
    }

    try {
      final attachment = await MediaAttachment.fromPath(
        path,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: source.fileSize,
      );
      final voiceNote = source.contentType == MessageContentType.voiceNote
          ? VoiceNoteMetadata(
              duration: source.voiceNoteDuration ?? Duration.zero,
              waveform: source.voiceNoteWaveform,
            )
          : null;
      final outcomes = await _media.send(
        conversationId: target.id,
        recipientId: target.peerId,
        attachments: [attachment],
        isGroup: target.isGroup,
        groupMembers: target.groupMembers,
        caption: source.caption,
        voiceNote: voiceNote,
      );
      return outcomes.single.result is FileTransferSuccess
          ? ForwardMessageOutcome.sent
          : ForwardMessageOutcome.deliveryFailed;
    } on FileSystemException {
      return ForwardMessageOutcome.sourceUnavailable;
    } on StateError {
      return ForwardMessageOutcome.deliveryFailed;
    }
  }
}

ForwardMessageOutcome _mapSendOutcome(SendMessageOutcome outcome) =>
    switch (outcome) {
      SendMessageOutcome.sent => ForwardMessageOutcome.sent,
      SendMessageOutcome.encryptionFailed =>
        ForwardMessageOutcome.encryptionFailed,
      SendMessageOutcome.deliveryFailed => ForwardMessageOutcome.deliveryFailed,
    };
