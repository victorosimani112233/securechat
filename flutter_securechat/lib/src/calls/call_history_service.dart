import '../media/call_models.dart';
import '../storage/secure_chat_database.dart';

enum CallHistoryStatus { completed, missed, rejected, busy, failed }

class CallHistoryEntry {
  const CallHistoryEntry({
    required this.peerId,
    required this.peerName,
    required this.callType,
    required this.direction,
    required this.status,
    required this.duration,
  });

  final String peerId;
  final String peerName;
  final CallType callType;
  final CallDirection direction;
  final CallHistoryStatus status;
  final Duration duration;
}

class CallHistoryService {
  const CallHistoryService(this._callLogs);

  final CallLogDao _callLogs;

  Stream<List<CallHistoryEntry>> watchAll() => _callLogs.getAll().map(
    (entries) => entries
        .map(
          (entry) => CallHistoryEntry(
            peerId: entry.peerId,
            peerName: entry.peerName,
            callType: entry.callType == 'VIDEO'
                ? CallType.video
                : CallType.voice,
            direction: entry.direction == 'OUTGOING'
                ? CallDirection.outgoing
                : CallDirection.incoming,
            status: _status(entry.status),
            duration: Duration(milliseconds: entry.duration),
          ),
        )
        .toList(growable: false),
  );

  static CallHistoryStatus _status(String value) => switch (value) {
    'ANSWERED' || 'COMPLETED' => CallHistoryStatus.completed,
    'MISSED' => CallHistoryStatus.missed,
    'REJECTED' => CallHistoryStatus.rejected,
    'BUSY' => CallHistoryStatus.busy,
    _ => CallHistoryStatus.failed,
  };
}
