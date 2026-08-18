import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

import org.whispersystems.libsignal.IdentityKeyPair;
import org.whispersystems.libsignal.SessionCipher;
import org.whispersystems.libsignal.SignalProtocolAddress;
import org.whispersystems.libsignal.groups.GroupCipher;
import org.whispersystems.libsignal.groups.GroupSessionBuilder;
import org.whispersystems.libsignal.groups.SenderKeyName;
import org.whispersystems.libsignal.groups.state.SenderKeyRecord;
import org.whispersystems.libsignal.groups.state.SenderKeyStore;
import org.whispersystems.libsignal.protocol.CiphertextMessage;
import org.whispersystems.libsignal.protocol.PreKeySignalMessage;
import org.whispersystems.libsignal.state.PreKeyRecord;
import org.whispersystems.libsignal.state.SignedPreKeyRecord;
import org.whispersystems.libsignal.state.impl.InMemorySignalProtocolStore;

/**
 * Test-only bridge compiled against the exact Java 2.8.1 dependency used by
 * the Kotlin application. It intentionally has no application/runtime role.
 */
public final class LegacySignalInterop {
  private static final Base64.Decoder DECODER = Base64.getDecoder();
  private static final Base64.Encoder ENCODER = Base64.getEncoder();

  public static void main(String[] args) throws Exception {
    if (args.length == 0) throw new IllegalArgumentException("mode required");
    if ("direct".equals(args[0])) {
      direct(args);
      return;
    }
    if ("group".equals(args[0])) {
      group(args);
      return;
    }
    throw new IllegalArgumentException("unknown mode: " + args[0]);
  }

  private static void direct(String[] args) throws Exception {
    if (args.length != 9) throw new IllegalArgumentException("direct args");
    IdentityKeyPair identity = new IdentityKeyPair(decode(args[1]));
    int registrationId = Integer.parseInt(args[2]);
    int preKeyId = Integer.parseInt(args[3]);
    int signedPreKeyId = Integer.parseInt(args[5]);
    InMemorySignalProtocolStore store =
        new InMemorySignalProtocolStore(identity, registrationId);
    store.storePreKey(preKeyId, new PreKeyRecord(decode(args[4])));
    store.storeSignedPreKey(
        signedPreKeyId,
        new SignedPreKeyRecord(decode(args[6])));

    SessionCipher cipher = new SessionCipher(
        store,
        new SignalProtocolAddress("dart-client", 1));
    byte[] plaintext = cipher.decrypt(new PreKeySignalMessage(decode(args[7])));
    CiphertextMessage reply = cipher.encrypt(args[8].getBytes(StandardCharsets.UTF_8));
    System.out.println(encode(plaintext));
    System.out.println(reply.getType());
    System.out.println(encode(reply.serialize()));
  }

  private static void group(String[] args) throws Exception {
    if (args.length != 3) throw new IllegalArgumentException("group args");
    MemorySenderKeyStore receiverStore = new MemorySenderKeyStore();
    SenderKeyName dartName = new SenderKeyName(
        "compat-group",
        new SignalProtocolAddress("dart-client", 1));
    GroupSessionBuilder receiverBuilder = new GroupSessionBuilder(receiverStore);
    receiverBuilder.process(
        dartName,
        new org.whispersystems.libsignal.protocol.SenderKeyDistributionMessage(
            decode(args[1])));
    byte[] plaintext = new GroupCipher(receiverStore, dartName).decrypt(decode(args[2]));

    MemorySenderKeyStore senderStore = new MemorySenderKeyStore();
    SenderKeyName javaName = new SenderKeyName(
        "compat-group",
        new SignalProtocolAddress("java-client", 1));
    GroupSessionBuilder senderBuilder = new GroupSessionBuilder(senderStore);
    byte[] distribution = senderBuilder.create(javaName).serialize();
    byte[] ciphertext = new GroupCipher(senderStore, javaName).encrypt(
        "java-group-reply".getBytes(StandardCharsets.UTF_8));

    System.out.println(encode(plaintext));
    System.out.println(encode(distribution));
    System.out.println(encode(ciphertext));
  }

  private static byte[] decode(String value) {
    return DECODER.decode(value);
  }

  private static String encode(byte[] value) {
    return ENCODER.encodeToString(value);
  }

  private static final class MemorySenderKeyStore implements SenderKeyStore {
    private final Map<SenderKeyName, SenderKeyRecord> records = new HashMap<>();

    @Override
    public void storeSenderKey(SenderKeyName name, SenderKeyRecord record) {
      records.put(name, record);
    }

    @Override
    public SenderKeyRecord loadSenderKey(SenderKeyName name) {
      SenderKeyRecord record = records.get(name);
      return record == null ? new SenderKeyRecord() : record;
    }
  }
}
