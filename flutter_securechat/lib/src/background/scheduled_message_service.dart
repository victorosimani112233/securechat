import 'dart:math';

import '../config/app_config.dart';
import '../domain/send_message_use_case.dart';
import '../services/session_store.dart';
import '../services/signaling_service.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';
import 'background_scheduler.dart';

enum ScheduledRepeat { once, daily, custom }

class ScheduledMessageDraft {
  const ScheduledMessageDraft({
    required this.content,
    required this.recipients,
    required this.recipientNames,
    required this.hour,
    required this.minute,
    this.repeat = ScheduledRepeat.once,
    this.days = const {},
  });

  final String content;
  final List<String> recipients;
  final List<String> recipientNames;
  final int hour;
  final int minute;
  final ScheduledRepeat repeat;
  final Set<int> days;
}

class ScheduledMessageService {
  ScheduledMessageService({
    required ScheduledMessageDao dao,
    required SendMessageUseCase sender,
    required SignalingService signaling,
    required SessionStore session,
    required BackgroundScheduler scheduler,
    DateTime Function()? now,
    Random? random,
  }) : _dao = dao,
       _sender = sender,
       _signaling = signaling,
       _session = session,
       _scheduler = scheduler,
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final ScheduledMessageDao _dao;
  final SendMessageUseCase _sender;
  final SignalingService _signaling;
  final SessionStore _session;
  final BackgroundScheduler _scheduler;
  final DateTime Function() _now;
  final Random _random;

  Stream<List<ScheduledMessageEntity>> watchAll() => _dao.getAll();

  Future<ScheduledMessageEntity> save(
    ScheduledMessageDraft draft, {
    String? id,
  }) async {
    final content = draft.content.trim();
    final recipients = draft.recipients
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (content.isEmpty) throw ArgumentError.value(content, 'content');
    if (recipients.isEmpty) {
      throw ArgumentError.value(recipients, 'recipients');
    }
    if (draft.hour < 0 ||
        draft.hour > 23 ||
        draft.minute < 0 ||
        draft.minute > 59) {
      throw ArgumentError('Scheduled time is outside the valid clock range');
    }
    final normalizedDays = draft.days
        .where((day) => day >= 1 && day <= 7)
        .toSet();
    if (draft.repeat == ScheduledRepeat.custom && normalizedDays.isEmpty) {
      throw ArgumentError('Custom repetition requires at least one weekday');
    }
    final existing = id == null ? null : await _dao.getById(id);
    final entity = ScheduledMessageEntity(
      id: id ?? _newId(),
      messageContent: content,
      repeatType: draft.repeat.name.toUpperCase(),
      repeatDays: draft.repeat == ScheduledRepeat.custom
          ? (normalizedDays.toList()..sort()).join(',')
          : null,
      hour: draft.hour,
      minute: draft.minute,
      recipientIds: recipients.join(','),
      recipientNames: draft.recipientNames.join(','),
      nextTriggerTime: calculateNextTrigger(
        hour: draft.hour,
        minute: draft.minute,
        repeat: draft.repeat,
        days: normalizedDays,
        now: _now(),
      ).millisecondsSinceEpoch,
      createdAt: existing?.createdAt,
    );
    await _dao.insert(entity);
    if (_session.scheduledMessagesEnabled) {
      await _scheduler.scheduleMessage(entity);
    }
    return entity;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final current = await _dao.getById(id);
    if (current == null) return;
    final next = enabled
        ? calculateNextTrigger(
            hour: current.hour,
            minute: current.minute,
            repeat: parseRepeat(current.repeatType),
            days: parseDays(current.repeatDays),
            now: _now(),
          ).millisecondsSinceEpoch
        : current.nextTriggerTime;
    final updated = current.copyWith(isEnabled: enabled, nextTriggerTime: next);
    await _dao.update(updated);
    if (enabled && _session.scheduledMessagesEnabled) {
      await _scheduler.scheduleMessage(updated);
    } else {
      await _scheduler.cancelScheduledMessage(id);
    }
  }

  Future<void> delete(String id) async {
    await _scheduler.cancelScheduledMessage(id);
    await _dao.deleteById(id);
  }

  Future<int> processDue() async {
    if (!_session.scheduledMessagesEnabled) return 0;
    final due = await _dao.getDueMessages(_now().millisecondsSinceEpoch);
    var processed = 0;
    for (final plan in due) {
      if (await processPlan(plan.id)) processed++;
    }
    return processed;
  }

  Future<void> setGloballyEnabled(bool enabled) async {
    final plans = await _dao.getAllImmediate();
    for (final plan in plans) {
      if (!plan.isEnabled) continue;
      if (enabled) {
        await _scheduler.scheduleMessage(plan);
      } else {
        await _scheduler.cancelScheduledMessage(plan.id);
      }
    }
    if (enabled) await processDue();
  }

  Future<bool> processPlan(String id) async {
    final plan = await _dao.getById(id);
    if (plan == null || !plan.isEnabled) return false;
    final recipients = _csv(plan.recipientIds);
    if (recipients.isEmpty) {
      await delete(id);
      return true;
    }
    if (!await _ensureConnected()) return false;

    for (final recipient in recipients) {
      try {
        await _sender(
          SendMessageRequest(
            conversationId: recipient,
            content: plan.messageContent,
          ),
        );
      } catch (_) {
        // One recipient must not prevent the remaining fan-out. SendMessageUseCase
        // persists its own FAILED state and never falls back to plaintext.
      }
    }

    final repeat = parseRepeat(plan.repeatType);
    if (repeat == ScheduledRepeat.once) {
      await delete(id);
    } else {
      final updated = plan.copyWith(
        nextTriggerTime: calculateNextTrigger(
          hour: plan.hour,
          minute: plan.minute,
          repeat: repeat,
          days: parseDays(plan.repeatDays),
          now: _now(),
        ).millisecondsSinceEpoch,
      );
      await _dao.update(updated);
      await _scheduler.scheduleMessage(updated);
    }
    return true;
  }

  Future<bool> _ensureConnected() async {
    if (_signaling.currentStatus.isConnected) return true;
    final userId = _session.userId;
    final token = _session.accessToken;
    if (userId == null || userId.isEmpty || token == null || token.isEmpty) {
      return false;
    }
    try {
      await _signaling.connect(
        userId: userId,
        url: AppConfig.current.signalingUrl,
        accessToken: token,
        tokenProvider: () async => _session.accessToken,
      );
      return _signaling.ensureConnected(timeout: const Duration(seconds: 8));
    } catch (_) {
      return false;
    }
  }

  String _newId() {
    final suffix = List.generate(
      16,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    return '${_now().microsecondsSinceEpoch}-$suffix';
  }

  static ScheduledRepeat parseRepeat(String value) =>
      switch (value.toUpperCase()) {
        'DAILY' => ScheduledRepeat.daily,
        'CUSTOM' => ScheduledRepeat.custom,
        _ => ScheduledRepeat.once,
      };

  static Set<int> parseDays(String? value) => value == null
      ? <int>{}
      : value
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .where((day) => day >= 1 && day <= 7)
            .toSet();

  static DateTime calculateNextTrigger({
    required int hour,
    required int minute,
    required ScheduledRepeat repeat,
    required Set<int> days,
    required DateTime now,
  }) {
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (repeat == ScheduledRepeat.once || repeat == ScheduledRepeat.daily) {
      if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
      return target;
    }
    final validDays = days.where((day) => day >= 1 && day <= 7).toSet();
    if (validDays.isEmpty) {
      if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
      return target;
    }
    for (var offset = 0; offset <= 7; offset++) {
      final candidate = target.add(Duration(days: offset));
      if (validDays.contains(candidate.weekday) && candidate.isAfter(now)) {
        return candidate;
      }
    }
    return target.add(const Duration(days: 7));
  }
}

List<String> _csv(String value) => value
    .split(',')
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toList(growable: false);
