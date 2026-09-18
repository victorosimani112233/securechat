package com.securechat.signaling

import org.signal.libsignal.metadata.certificate.ServerCertificate
import org.signal.libsignal.protocol.ecc.Curve
import org.signal.libsignal.protocol.ecc.ECPrivateKey
import java.util.Base64
import java.util.Optional

/** Issues short-lived official-libsignal sender certificates. */
object SealedSenderCertificateIssuer {
    data class IssuedCertificate(
        val certificate: ByteArray,
        val expiresAt: Long,
        val trustRootPublicKey: ByteArray,
        val serverKeyId: Int,
    )

    private const val SERVER_KEY_ID = 1
    private const val CERTIFICATE_TTL_MILLIS = 24L * 60L * 60L * 1000L

    @Volatile
    private var state: State? = null

    internal data class State(
        val trustRootPublicKey: ByteArray,
        val serverPrivateKey: ECPrivateKey,
        val serverCertificate: ServerCertificate,
    )

    fun initialize(environment: Map<String, String> = System.getenv()) {
        state ?: synchronized(this) {
            state ?: load(environment).also { state = it }
        }
    }

    fun issue(
        senderId: String,
        senderIdentityPublicKey: ByteArray,
        nowMillis: Long = System.currentTimeMillis(),
    ): IssuedCertificate {
        val current = state ?: load(System.getenv()).also { loaded ->
            synchronized(this) { if (state == null) state = loaded }
        }
        val expiration = Math.addExact(nowMillis, CERTIFICATE_TTL_MILLIS)
        val identityPublicKey = Curve.decodePoint(senderIdentityPublicKey, 0)
        val certificate = current.serverCertificate.issue(
            current.serverPrivateKey,
            senderId,
            Optional.empty(),
            1,
            identityPublicKey,
            expiration,
        )
        return IssuedCertificate(
            certificate = certificate.serialized,
            expiresAt = expiration,
            trustRootPublicKey = current.trustRootPublicKey,
            serverKeyId = SERVER_KEY_ID,
        )
    }

    fun trustRootPublicKey(): ByteArray {
        val current = state ?: load(System.getenv()).also { loaded ->
            synchronized(this) { if (state == null) state = loaded }
        }
        return current.trustRootPublicKey
    }

    /**
     * Tercih edilen production bicimi: cevrimdisi imzalanmis server certificate.
     *
     * Trust root, istemci binary'sine pinlenir; ele gecirilmesi ancak yeni bir
     * uygulama surumuyle geri alinabilir. Bu yuzden ozel anahtari internete
     * bakan relay'de hic bulunmamalidir — sunucunun calismak icin ihtiyaci
     * olan tek sey, trust root tarafindan bir kez imzalanmis sertifika ve ona
     * karsilik gelen server anahtaridir.
     *
     * `SEALED_SENDER_SERVER_CERTIFICATE` verilmisse trust root ozel anahtari
     * hic istenmez. Verilmemisse sertifika process icinde uretilir; bu yalniz
     * gelistirme/test icindir ve production'da reddedilir.
     */
    internal fun load(environment: Map<String, String>): State {
        val server = decodePrivateKey(
            "SEALED_SENDER_SERVER_PRIVATE_KEY",
            SecretSource.required("SEALED_SENDER_SERVER_PRIVATE_KEY", environment),
        )
        val offlineCertificate = SecretSource.optional("SEALED_SENDER_SERVER_CERTIFICATE", environment)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (offlineCertificate != null) {
            val serialized = try {
                Base64.getDecoder().decode(offlineCertificate)
            } catch (_: IllegalArgumentException) {
                error("SEALED_SENDER_SERVER_CERTIFICATE must be valid Base64")
            }
            val certificate = ServerCertificate(serialized)
            require(certificate.keyId == SERVER_KEY_ID) {
                "SEALED_SENDER_SERVER_CERTIFICATE carries an unexpected key id"
            }
            require(certificate.key.serialize().contentEquals(server.publicKey().serialize())) {
                "SEALED_SENDER_SERVER_CERTIFICATE does not match SEALED_SENDER_SERVER_PRIVATE_KEY"
            }
            val pinnedTrustRoot = SecretSource.required(
                "SEALED_SENDER_TRUST_ROOT_PUBLIC_KEY",
                environment,
            ).trim()
            val trustRootPublic = try {
                Base64.getDecoder().decode(pinnedTrustRoot)
            } catch (_: IllegalArgumentException) {
                error("SEALED_SENDER_TRUST_ROOT_PUBLIC_KEY must be valid Base64")
            }
            // Sertifikanin gercekten pinlenmis trust root tarafindan
            // imzalandigi dogrulanir. Yanlis eslenmis bir cift sessizce
            // yuklenirse sunucu saglikli gorunur ama urettigi her zarf
            // istemcilerde reddedilir; hata baslangicta yakalanmalidir.
            require(
                Curve.verifySignature(
                    Curve.decodePoint(trustRootPublic, 0),
                    certificate.certificate,
                    certificate.signature,
                ),
            ) { "SEALED_SENDER_SERVER_CERTIFICATE is not signed by the pinned trust root" }
            return State(
                trustRootPublicKey = trustRootPublic,
                serverPrivateKey = server,
                serverCertificate = certificate,
            )
        }

        require(DeploymentProfile.isDevelopment(environment)) {
            "Production requires an offline-issued SEALED_SENDER_SERVER_CERTIFICATE; " +
                "the trust-root private key must not be present on the relay"
        }
        val trustRoot = decodePrivateKey(
            "SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY",
            SecretSource.required("SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY", environment),
        )
        require(!trustRoot.serialize().contentEquals(server.serialize())) {
            "Sealed Sender trust-root and server keys must be different"
        }
        return State(
            trustRootPublicKey = trustRoot.publicKey().serialize(),
            serverPrivateKey = server,
            serverCertificate = ServerCertificate(
                trustRoot,
                SERVER_KEY_ID,
                server.publicKey(),
            ),
        )
    }

    private fun decodePrivateKey(name: String, encoded: String): ECPrivateKey {
        val bytes = try {
            Base64.getDecoder().decode(encoded.trim())
        } catch (_: IllegalArgumentException) {
            error("$name must be valid Base64")
        }
        require(bytes.size == 32) { "$name must decode to exactly 32 bytes" }
        SecretPolicy.requireStrongKey(name, bytes)
        return Curve.decodePrivatePoint(bytes)
    }
}
