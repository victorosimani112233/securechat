import 'package:workmanager/workmanager.dart';

import '../storage/storage_entities.dart';

abstract interface class BackgroundScheduler {
  Future<void> initialize();
  Future<void> registerRecurringTasks();
  Future<void> scheduleMessage(ScheduledMessageEntity message);
  Future<void> cancelScheduledMessage(String id);
}

class WorkmanagerBackgroundScheduler implements BackgroundScheduler {
  const WorkmanagerBackgroundScheduler({
    required this.callbackDispatcher,
    this.executingPlanId,
  });

  final Function callbackDispatcher;

  /// Set only on the scheduler owned by a scheduled-message worker.
  /// Foreground schedulers must remain unscoped so user cancellation still works.
  final String? executingPlanId;

  static const scheduledMessageTask = 'securechat.scheduled-message';
  static const maintenanceTask = 'com.securechat.app.background.maintenance';
  static const senderKeyRotationTask =
      'com.securechat.app.background.sender-key-rotation';
  static const pushDrainTask = 'securechat.push-drain';
  static const _scheduledTag = 'securechat-scheduled-messages';

  String _uniqueMessageName(String id) => 'securechat-scheduled-$id';

  @override
  Future<void> initialize() => Workmanager().initialize(callbackDispatcher);

  @override
  Future<void> registerRecurringTasks() async {
    await Workmanager().registerPeriodicTask(
      maintenanceTask,
      maintenanceTask,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
    await Workmanager().registerPeriodicTask(
      senderKeyRotationTask,
      senderKeyRotationTask,
      frequency: const Duration(days: 7),
      initialDelay: const Duration(days: 7),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }

  @override
  Future<void> scheduleMessage(ScheduledMessageEntity message) async {
    await cancelScheduledMessage(message.id);
    if (!message.isEnabled) return;
    final delayMs =
        message.nextTriggerTime - DateTime.now().millisecondsSinceEpoch;
    await Workmanager().registerOneOffTask(
      _uniqueMessageName(message.id),
      scheduledMessageTask,
      inputData: {'planId': message.id},
      initialDelay: Duration(milliseconds: delayMs > 0 ? delayMs : 0),
      constraints: Constraints(networkType: NetworkType.connected),
      // The installed Android plugin maps append to APPEND_OR_REPLACE, keeping
      // the current worker alive until delivery draining and teardown finish.
      existingWorkPolicy: message.id == executingPlanId
          ? ExistingWorkPolicy.append
          : ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
      tag: _scheduledTag,
    );
  }

  @override
  Future<void> cancelScheduledMessage(String id) async {
    if (id == executingPlanId) return;
    await Workmanager().cancelByUniqueName(_uniqueMessageName(id));
  }
}
