import '../media/call_models.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';

enum CallHistoryStatus { completed, missed, rejected, busy, failed }

class CallHistoryEntry {
  const CallHistoryEntry({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.callType,
    required this.direction,
    required this.status,
    required this.timestamp,
    required this.duration,
    this.groupId,
  });

  final String id;
  final String peerId;
  final String peerName;
  final CallType callType;
  final CallDirection direction;
  final CallHistoryStatus status;
  final DateTime timestamp;
  final Duration duration;
  final String? groupId;
}

class CallHistoryService {
  const CallHistoryService(this._callLogs);

  final CallLogDao _callLogs;

  Stream<List<CallHistoryEntry>> watchAll() => _callLogs.getAll().map(_entries);

  Stream<List<CallHistoryEntry>> watchPeer(String peerId) =>
      _callLogs.getByPeerId(peerId).map(_entries);

  Future<void> delete(String callId) => _callLogs.deleteById(callId);

  static List<CallHistoryEntry> _entries(List<CallLogEntity> entries) =>
      entries.map(_entry).toList(growable: false);

  static CallHistoryEntry _entry(CallLogEntity entry) => CallHistoryEntry(
    id: entry.id,
    peerId: entry.peerId,
    peerName: entry.peerName,
    callType: entry.callType == 'VIDEO' ? CallType.video : CallType.voice,
    direction: entry.direction == 'OUTGOING'
        ? CallDirection.outgoing
        : CallDirection.incoming,
    status: _status(entry.status),
    timestamp: DateTime.fromMillisecondsSinceEpoch(entry.timestamp),
    duration: Duration(milliseconds: entry.duration),
    groupId: entry.groupId,
  );

  static CallHistoryStatus _status(String value) => switch (value) {
    'ANSWERED' || 'COMPLETED' => CallHistoryStatus.completed,
    'MISSED' => CallHistoryStatus.missed,
    'REJECTED' => CallHistoryStatus.rejected,
    'BUSY' => CallHistoryStatus.busy,
    _ => CallHistoryStatus.failed,
  };
}
