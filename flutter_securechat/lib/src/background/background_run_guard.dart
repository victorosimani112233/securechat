import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

/// Surec capinda tek arka plan calistiricisi (QA 2026-10-14).
///
/// FCM eklentisi soguk baslangicta ayni surecte iki arka plan motoru
/// acabiliyor; WorkManager da kendi motorunu aciyor. Her motor kendi
/// isolate'inde ayni sifreli veritabanini ve oturumu acip ayni kuyrugu
/// bosaltinca ayni mesaj iki kez cozulmeye calisiliyor (ratchet bir kez
/// ilerler, ikinci deneme `missingMessageKey` ile duser ve mesaj kaybolur).
///
/// `IsolateNameServer` surecteki tum motorlarca paylasilir. Sahip, adi
/// verilen porta gelen her yoklamayi yanitlar; yanit gelmezse sahip olmus
/// sayilir ve kayit devralinir. Boylece coken bir motor kilidi kalici olarak
/// tutamaz.
class BackgroundRunGuard {
  BackgroundRunGuard._(this._port);

  static const portName = 'securechat.background-runner';

  final ReceivePort _port;

  /// [action]'i surecteki diger arka plan calismalariyla siraya sokarak
  /// kosturur. [wait] icinde sira gelmezse `null` doner ve eylem kosmaz.
  static Future<T?> run<T>(
    Future<T> Function() action, {
    Duration wait = const Duration(minutes: 2),
    Duration probe = const Duration(seconds: 1),
  }) async {
    final guard = await _acquire(wait: wait, probe: probe);
    if (guard == null) return null;
    try {
      return await action();
    } finally {
      guard._release();
    }
  }

  static Future<BackgroundRunGuard?> _acquire({
    required Duration wait,
    required Duration probe,
  }) async {
    final deadline = DateTime.now().add(wait);
    var delay = const Duration(milliseconds: 50);
    while (true) {
      final port = ReceivePort();
      if (IsolateNameServer.registerPortWithName(port.sendPort, portName)) {
        final guard = BackgroundRunGuard._(port);
        port.listen(guard._answer);
        return guard;
      }
      port.close();
      final owner = IsolateNameServer.lookupPortByName(portName);
      if (owner != null && !await _isAlive(owner, probe)) {
        // Sahip yanit vermedi: motoru kapanmis. Yalniz hala ayni kayitsa
        // sil; arada baskasi devraldiysa onun kaydina dokunma.
        if (IsolateNameServer.lookupPortByName(portName) == owner) {
          IsolateNameServer.removePortNameMapping(portName);
        }
        continue;
      }
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(delay);
      if (delay < const Duration(milliseconds: 400)) delay *= 2;
    }
  }

  static Future<bool> _isAlive(SendPort owner, Duration probe) async {
    final reply = ReceivePort();
    try {
      owner.send(reply.sendPort);
      await reply.first.timeout(probe);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      reply.close();
    }
  }

  void _answer(Object? message) {
    if (message is SendPort) message.send(true);
  }

  void _release() {
    if (IsolateNameServer.lookupPortByName(portName) == _port.sendPort) {
      IsolateNameServer.removePortNameMapping(portName);
    }
    _port.close();
  }
}
