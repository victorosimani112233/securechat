package com.securechat.signaling.tools

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import java.util.Base64
import org.signal.libsignal.metadata.certificate.ServerCertificate
import org.signal.libsignal.protocol.ecc.Curve
import org.signal.libsignal.protocol.ecc.ECPrivateKey

/**
 * Sealed Sender anahtar hiyerarsisini **cevrimdisi** bir makinede uretir.
 *
 * Trust root, istemci binary'sine pinlenir. Ozel anahtari ele geciren biri
 * istedigi hesap adina gecerli bir sender certificate uretebilir ve bu ancak
 * yeni bir uygulama surumuyle geri alinabilir. Bu yuzden trust root ozel
 * anahtari internete bakan relay'e hicbir zaman kopyalanmaz: relay'in ihtiyaci
 * olan tek sey, trust root tarafindan bir kez imzalanmis server certificate ve
 * ona karsilik gelen server ozel anahtaridir.
 *
 * Calistirma (ag baglantisi olmayan bir makinede):
 *
 * ```
 * java -cp signaling-server-all.jar \
 *   com.securechat.signaling.tools.SealedSenderOfflineKeygen /secure/offline/sealed-sender
 * ```
 *
 * Uretilen dosyalar:
 *
 * | Dosya                     | Nereye gider                                   |
 * |---------------------------|------------------------------------------------|
 * | `trust_root_private_key`  | Yalniz cevrimdisi kasada kalir. Asla kopyalanmaz |
 * | `trust_root_public_key`   | Mobil build'e pinlenir ve relay'e verilir      |
 * | `server_private_key`      | Relay secret'i                                  |
 * | `server_certificate`      | Relay secret'i                                  |
 */
object SealedSenderOfflineKeygen {

    private const val SERVER_KEY_ID = 1

    @JvmStatic
    fun main(args: Array<String>) {
        if (args.size != 1) {
            System.err.println(
                "kullanim: SealedSenderOfflineKeygen <cikis-dizini>\n" +
                    "Cikis dizini bos olmalidir ve cevrimdisi bir makinede bulunmalidir.",
            )
            kotlin.system.exitProcess(2)
        }
        val outputDirectory = Path.of(args[0]).toAbsolutePath()
        Files.createDirectories(outputDirectory)
        // Var olan bir anahtarin uzerine yazmak, hala kullanimda olan bir
        // trust root'u sessizce kaybetmek demektir.
        val existing = Files.list(outputDirectory).use { it.findFirst() }
        require(existing.isEmpty) { "Cikis dizini bos olmali: $outputDirectory" }

        val trustRoot = Curve.generateKeyPair()
        val server = Curve.generateKeyPair()
        val certificate = ServerCertificate(
            trustRoot.privateKey,
            SERVER_KEY_ID,
            server.publicKey,
        )

        write(outputDirectory.resolve("trust_root_private_key"), trustRoot.privateKey.serialize())
        write(outputDirectory.resolve("trust_root_public_key"), trustRoot.publicKey.serialize())
        write(outputDirectory.resolve("server_private_key"), server.privateKey.serialize())
        write(outputDirectory.resolve("server_certificate"), certificate.serialized)

        // Uretilen ciftin gercekten birbirine uydugu burada dogrulanir; yanlis
        // eslenmis bir set relay'de saglikli gorunur ama her zarf istemcide
        // reddedilirdi.
        check(
            Curve.verifySignature(
                trustRoot.publicKey,
                certificate.certificate,
                certificate.signature,
            ),
        ) { "Uretilen sertifika trust root ile dogrulanamadi" }
        checkRoundTrip(server.privateKey, certificate)

        println("Sealed Sender anahtarlari yazildi: $outputDirectory")
        println()
        println("  trust_root_private_key -> CEVRIMDISI KASA. Sunucuya kopyalamayin.")
        println("  trust_root_public_key  -> mobil build girdisi + relay secret'i")
        println("  server_private_key     -> relay secret'i")
        println("  server_certificate     -> relay secret'i")
    }

    /** Sertifikanin gercekten bu server anahtariyla sender certificate uretebildigini dogrular. */
    private fun checkRoundTrip(serverPrivateKey: ECPrivateKey, certificate: ServerCertificate) {
        val sender = Curve.generateKeyPair()
        certificate.issue(
            serverPrivateKey,
            "00000000-0000-4000-8000-000000000000",
            java.util.Optional.empty(),
            1,
            sender.publicKey,
            System.currentTimeMillis() + 60_000L,
        )
    }

    private fun write(path: Path, material: ByteArray) {
        val encoded = Base64.getEncoder().encodeToString(material)
        Files.writeString(path, encoded)
        runCatching {
            Files.setPosixFilePermissions(path, PosixFilePermissions.fromString("rw-------"))
        }
    }
}
