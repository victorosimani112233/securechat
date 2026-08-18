import 'dart:async';
import 'dart:io';

import '../auth/auth_coordinator.dart';
import '../background/scheduled_message_service.dart';
import '../storage/secure_chat_database.dart';

typedef PushUnregister = Future<bool> Function();

class AccountDataService {
  AccountDataService({
    required AuthCoordinator auth,
    required SecureChatDatabase database,
    required ScheduledMessageService scheduledMessages,
    required List<Directory> managedDirectories,
    PushUnregister? unregisterPush,
    Future<void> Function()? afterLocalCleanup,
  }) : _auth = auth,
       _database = database,
       _scheduledMessages = scheduledMessages,
       _managedDirectories = List.unmodifiable(managedDirectories),
       _unregisterPush = unregisterPush,
       _afterLocalCleanup = afterLocalCleanup;

  final AuthCoordinator _auth;
  final SecureChatDatabase _database;
  final ScheduledMessageService _scheduledMessages;
  final List<Directory> _managedDirectories;
  final PushUnregister? _unregisterPush;
  final Future<void> Function()? _afterLocalCleanup;
  Future<void>? _activeOperation;

  Future<void> deleteLocalData() => _once(() async {
    await _unregisterPushBestEffort();
    await _disableScheduledBestEffort();
    // AuthCoordinator guarantees local logout even if its HTTP revoke fails.
    await _auth.logout();
    try {
      await _clearDeviceData();
    } finally {
      await _afterLocalCleanup?.call();
    }
  });

  Future<void> deleteAccount() => _once(() async {
    await _unregisterPushBestEffort();
    // Do not destroy local authentication before the authenticated endpoint
    // has acknowledged the irreversible server-side deletion.
    await _auth.deleteAccountOnServer();
    await _disableScheduledBestEffort();
    try {
      await _clearDeviceData();
    } finally {
      // A deleted account must never retain usable local credentials, even if
      // a filesystem cleanup reports an error.
      await _auth.clearLocalAuthentication();
      await _afterLocalCleanup?.call();
    }
  });

  Future<void> _clearDeviceData() async {
    await _database.clearAll();
    for (final directory in _managedDirectories) {
      if (!await directory.exists()) continue;
      await directory.delete(recursive: true);
    }
  }

  Future<void> _unregisterPushBestEffort() async {
    try {
      await _unregisterPush?.call();
    } catch (_) {
      // Account/data deletion must remain possible while push is unavailable.
    }
  }

  Future<void> _disableScheduledBestEffort() async {
    try {
      await _scheduledMessages.setGloballyEnabled(false);
    } catch (_) {
      // The encrypted database is cleared below; a stale platform callback
      // will therefore find no plan and cannot send a message.
    }
  }

  Future<void> _once(Future<void> Function() operation) {
    final active = _activeOperation;
    if (active != null) return active;
    final next = operation();
    _activeOperation = next;
    return next.whenComplete(() {
      if (identical(_activeOperation, next)) _activeOperation = null;
    });
  }
}
