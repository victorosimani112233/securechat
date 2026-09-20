import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresyon: sistem bildirimindeki "Reddet" ile aktif cagridaki "Kapat"
/// ayni native aksiyona (`end`) dusuyor. Ikisi ayni sinyali gonderirse
/// arayan taraf "reddedildi" ile "gorusme bitti" ayrimini yapamaz.
///
/// Cihaz turunde olculen davranis: gelen cagri calarken Reddet'e basildiginda
/// wire'a `HANGUP` gidiyordu.
void main() {
  CallSession session(CallDirection direction, CallState state) => CallSession(
    callId: 'c1',
    peerId: 'peer',
    peerName: 'Peer',
    callType: CallType.voice,
    direction: direction,
    state: state,
  );

  test('kabul edilmemis gelen cagri reddetme sayilir', () {
    for (final state in [CallState.ringing, CallState.initiating]) {
      expect(
        isUnansweredIncomingCall(session(CallDirection.incoming, state)),
        isTrue,
        reason: '$state durumunda Reddet REJECT gondermeli',
      );
    }
  });

  test('aktif cagri kapatma reddetme degildir', () {
    for (final state in [
      CallState.active,
      CallState.connecting,
      CallState.reconnecting,
    ]) {
      expect(
        isUnansweredIncomingCall(session(CallDirection.incoming, state)),
        isFalse,
        reason: '$state durumunda HANGUP gonderilmeli',
      );
    }
  });

  test('giden cagriyi iptal etmek reddetme degildir', () {
    expect(
      isUnansweredIncomingCall(
        session(CallDirection.outgoing, CallState.ringing),
      ),
      isFalse,
    );
  });
}
