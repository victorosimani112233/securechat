package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import java.util.Base64
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import org.junit.jupiter.api.*
import org.junit.jupiter.api.Assertions.*
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.containers.GenericContainer
import org.testcontainers.utility.DockerImageName
import io.ktor.client.request.*
import io.ktor.client.statement.bodyAsText
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.install
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class RecoveryAuthIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16")
    private val redis = GenericContainer(DockerImageName.parse("redis:7-alpine")).withExposedPorts(6379)
    private val codes = ConcurrentHashMap<String, String>()
    private lateinit var service: RecoveryAuthService
    private lateinit var cipher: RecoveryRecordCipher
    private data class Fixture(val user: String, val email: String, val key: KeyPair, val epoch: String)

    @BeforeAll fun setup() {
        Assumptions.assumeTrue(DockerClientFactory.instance().isDockerAvailable)
        postgres.start(); redis.start()
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        Database.ensureSchema()
        RedisManager.init(redis.host, redis.getMappedPort(6379), null)
        cipher = RecoveryRecordCipher.configured()!!
        service = RecoveryAuthService(cipher) { email, code, purpose -> codes["$purpose:$email"] = code }
    }
    @AfterAll fun cleanup() {
        runCatching { Database.close() }; runCatching { RedisManager.close() }
        postgres.stop(); redis.stop()
    }

    private fun fixture(): Fixture {
        val user = UUID.randomUUID().toString()
        val pair = ed25519()
        Database.getConnection().use { connection ->
            // `signing_public_key`: kurtarma artik Ed25519 imzalama anahtarini
            // pinliyor. `identity_public_key`: libsignal bundle yolu (PreKeyStore)
            // icin ayri bir sahte 33 bayt kimlik; kurtarmadan ayrik.
            connection.prepareStatement("INSERT INTO users(user_id, directory_token, identity_public_key, signing_public_key, registration_id) VALUES (?::uuid, ?, ?, ?, 1234)").use {
                it.setString(1, user); it.setString(2, "pending:$user")
                it.setBytes(3, ByteArray(33) { i -> i.toByte() }); it.setBytes(4, pub(pair)); it.executeUpdate()
            }
        }
        return Fixture(user, "$user@example.com", pair, CredentialState.snapshot(user)!!.credentialEpoch)
    }
    private fun ed25519(): KeyPair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
    // JDK Ed25519 X.509/SPKI ciktisi verir; ham 32 bayt icin 12 baytlik oneki soy.
    private fun pub(pair: KeyPair): ByteArray = pair.public.encoded.copyOfRange(12, 44)
    private fun sign(pair: KeyPair, bytes: String) = Base64.getEncoder().encodeToString(
        Signature.getInstance("Ed25519").run { initSign(pair.private); update(bytes.toByteArray(Charsets.UTF_8)); sign() })
    private fun enrollment(f: Fixture): Pair<RecoveryEnrollmentChallenge, RecoveryVerify> {
        val challenge = service.requestEnrollment(f.user, f.epoch, f.email)!!
        val context = RecoveryAuthService.Context(f.user, f.email, f.epoch, challenge.nonce, challenge.identityProtocol)
        return challenge to RecoveryVerify(challenge.challengeId, codes["enroll:${f.email}"]!!,
            sign(f.key, RecoveryAuthService.enrollmentPreimage(challenge.challengeId, context)))
    }
    private fun bind(f: Fixture) {
        assertTrue(service.verifyEnrollment(f.user, f.epoch, enrollment(f).second))
    }
    private fun grant(f: Fixture): RecoveryGrant {
        val challenge = service.requestLogin(f.email)
        return service.verifyLogin(RecoveryVerify(challenge.challengeId, codes["login:${f.email}"]!!))!!
    }
    private fun completion(f: Fixture, grant: RecoveryGrant, key: KeyPair = f.key, mode: String = "preserve", protocol: String = "olm"): RecoveryComplete {
        val unsigned = RecoveryComplete(grant.recoveryToken, RecoveryRecordCipher.opaque(), mode, protocol,
            Base64.getEncoder().encodeToString(pub(key)), 1234, "")
        return unsigned.copy(signature = sign(key, RecoveryAuthService.completionPreimage(f.user, unsigned)))
    }
    private fun signingKey(user: String): ByteArray? = Database.getConnection().use { connection ->
        connection.prepareStatement("SELECT signing_public_key FROM users WHERE user_id = ?::uuid").use {
            it.setString(1, user); it.executeQuery().use { rows -> if (rows.next()) rows.getBytes(1) else null }
        }
    }
    private fun count(table: String, column: String, value: String): Int = Database.getConnection().use { connection ->
        connection.prepareStatement("SELECT COUNT(*) FROM $table WHERE $column = ?").use {
            it.setString(1, value); it.executeQuery().use { rows -> rows.next(); rows.getInt(1) }
        }
    }

    @Test fun `binding requires current identity proof and cannot be replaced`() {
        val f = fixture()
        assertFalse(service.enrolled(f.user, f.epoch))
        val bad = enrollment(f).second.copy(signature = Base64.getEncoder().encodeToString(ByteArray(64)))
        assertFalse(service.verifyEnrollment(f.user, f.epoch, bad))
        bind(f)
        assertTrue(service.enrolled(f.user, f.epoch))
        assertNull(service.requestEnrollment(f.user, f.epoch, "different@example.com"))
    }

    @Test fun `HTTP contract includes explicit expiry status generic preauth and identical completion retry`() = testApplication {
        RedisManager.use { it.flushDB() }
        application {
            install(ContentNegotiation) { json() }
            routing { recoveryAuthRoutes() }
        }
        val f = fixture()
        val access = AuthService.issueToken(f.user)
        val unauthenticated = client.post("/api/v1/account/recovery-email/status") {
            contentType(ContentType.Application.Json); setBody("{}")
        }
        assertEquals(HttpStatusCode.Unauthorized, unauthenticated.status)
        val enrollment = enrollment(f).second
        val verified = client.post("/api/v1/account/recovery-email/verify") {
            bearerAuth(access); contentType(ContentType.Application.Json); setBody(Json.encodeToString(enrollment))
        }
        assertEquals(HttpStatusCode.OK, verified.status)
        assertEquals("{\"status\":\"ok\"}", verified.bodyAsText())
        val status = client.post("/api/v1/account/recovery-email/status") {
            bearerAuth(access); contentType(ContentType.Application.Json); setBody("{}")
        }
        assertEquals("{\"bound\":true}", status.bodyAsText())
        for (email in listOf(f.email, "${UUID.randomUUID()}@example.com")) {
            val response = client.post("/api/v1/auth/login/request") {
                contentType(ContentType.Application.Json); setBody(Json.encodeToString(RecoveryRequest(email)))
            }
            assertEquals(HttpStatusCode.OK, response.status)
            assertEquals("no-store", response.headers["Cache-Control"])
            val body = Json.parseToJsonElement(response.bodyAsText()).jsonObject
            assertEquals(setOf("challengeId", "expiresIn"), body.keys)
            assertEquals("600", body["expiresIn"].toString())
        }
        val challenge = service.requestLogin(f.email)
        val verifiedLogin = client.post("/api/v1/auth/login/verify") {
            contentType(ContentType.Application.Json)
            setBody(Json.encodeToString(RecoveryVerify(challenge.challengeId, codes["login:${f.email}"]!!)))
        }
        assertEquals(HttpStatusCode.OK, verifiedLogin.status)
        val grant = Json.decodeFromString<RecoveryGrant>(verifiedLogin.bodyAsText())
        assertEquals(300, grant.expiresIn)
        val request = completion(f, grant)
        val first = client.post("/api/v1/auth/login/complete") {
            contentType(ContentType.Application.Json); setBody(Json.encodeToString(request))
        }
        val retry = client.post("/api/v1/auth/login/complete") {
            contentType(ContentType.Application.Json); setBody(Json.encodeToString(request))
        }
        assertEquals(HttpStatusCode.OK, first.status)
        assertEquals(first.bodyAsText(), retry.bodyAsText())
        assertTrue(Json.parseToJsonElement(first.bodyAsText()).jsonObject.containsKey("token"))
    }

    @Test fun `HTTP registration lock endpoints and the locked completion response`() = testApplication {
        RedisManager.use { it.flushDB() }
        application {
            install(ContentNegotiation) { json() }
            routing { recoveryAuthRoutes() }
        }
        val f = fixture(); bind(f)
        val access = AuthService.issueToken(f.user, f.epoch)
        suspend fun post(path: String, body: String, auth: Boolean = true) = client.post(path) {
            if (auth) bearerAuth(access)
            contentType(ContentType.Application.Json); setBody(body)
        }
        assertEquals(HttpStatusCode.Unauthorized, post("/api/v1/account/registration-lock/status", "{}", auth = false).status)
        assertEquals("{\"enabled\":false}", post("/api/v1/account/registration-lock/status", "{}").bodyAsText())
        // Bicimsiz kanit reddedilir.
        assertEquals(HttpStatusCode.BadRequest, post("/api/v1/account/registration-lock", "{\"proof\":\"kisa\"}").status)
        assertEquals(HttpStatusCode.OK, post("/api/v1/account/registration-lock", "{\"proof\":\"${lockProof(3)}\"}").status)
        assertEquals("{\"enabled\":true}", post("/api/v1/account/registration-lock/status", "{}").bodyAsText())

        val request = completion(f, grant(f), ed25519(), "replace")
        val locked = post("/api/v1/auth/login/complete", Json.encodeToString(request), auth = false)
        assertEquals(HttpStatusCode.Locked, locked.status)
        val body = Json.parseToJsonElement(locked.bodyAsText()).jsonObject
        assertEquals("\"registration_lock\"", body["error"].toString())
        assertEquals("\"${RegistrationLock.MAX_FAILURES - 1}\"", body["remainingAttempts"].toString())
        val ok = post("/api/v1/auth/login/complete", Json.encodeToString(request.copy(lockProof = lockProof(3))), auth = false)
        assertEquals(HttpStatusCode.OK, ok.status)
    }

    @Test fun `queued old delete logout and prekey writes cannot mutate a recovered epoch`() {
        for (operation in listOf("delete", "logout", "prekey")) {
            val f = fixture()
            val claims = AuthService.accessClaims(AuthService.issueToken(f.user))!!
            val newEpoch = RecoveryRecordCipher.opaque()
            val pool = Executors.newSingleThreadExecutor()
            try {
                Database.getConnection().use { blocker ->
                    blocker.autoCommit = false
                    blocker.prepareStatement("SELECT user_id FROM users WHERE user_id = ?::uuid FOR UPDATE").use {
                        it.setString(1, f.user); it.executeQuery().close()
                    }
                    val oldRequest = pool.submit(Callable {
                        runCatching {
                            when (operation) {
                                "delete" -> AccountDeletion.deleteDurableState(claims.userId, claims.epoch)
                                "logout" -> AuthService.revokeAllTokens(claims.userId, claims.epoch)
                                else -> {
                                    PreKeyStore.addOneTimePreKeys(claims.userId,
                                        listOf(PreKeyStore.OneTimePreKey(991, ByteArray(33))), claims.epoch)
                                    true
                                }
                            }
                        }.getOrDefault(false)
                    })
                    // Observe the old request blocked on the account, not an arbitrary sleep.
                    val deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(5)
                    var waiting = false
                    while (!waiting && System.nanoTime() < deadline) {
                        Database.getConnection().use { observer ->
                            observer.createStatement().use { statement ->
                                statement.executeQuery("SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock')").use {
                                    it.next(); waiting = it.getBoolean(1)
                                }
                            }
                        }
                        if (!waiting) Thread.sleep(10)
                    }
                    assertTrue(waiting, "$operation did not reach the locked account")
                    blocker.prepareStatement("UPDATE users SET credential_epoch = ?, refresh_generation = ? WHERE user_id = ?::uuid").use {
                        it.setString(1, newEpoch); it.setString(2, RecoveryRecordCipher.opaque()); it.setString(3, f.user); it.executeUpdate()
                    }
                    blocker.commit()
                    assertFalse(oldRequest.get(5, java.util.concurrent.TimeUnit.SECONDS), operation)
                }
                assertEquals(newEpoch, CredentialState.snapshot(f.user)!!.credentialEpoch)
                assertEquals(0, PreKeyStore.unconsumedCount(f.user))
            } finally { pool.shutdownNow() }
        }
    }

    @Test fun `enrollment is epoch bound and replay protected`() {
        val f = fixture()
        val request = enrollment(f).second
        CredentialState.rotateCredentialEpoch(f.user)
        assertFalse(service.verifyEnrollment(f.user, f.epoch, request))
        assertFalse(service.verifyEnrollment(f.user, CredentialState.snapshot(f.user)!!.credentialEpoch, request))
        val fresh = fixture()
        val valid = enrollment(fresh).second
        assertTrue(service.verifyEnrollment(fresh.user, fresh.epoch, valid))
        assertFalse(service.verifyEnrollment(fresh.user, fresh.epoch, valid))
    }

    @Test fun `unknown addresses have generic challenges and no grant or mail`() {
        val email = "${UUID.randomUUID()}@example.com"
        val challenge = service.requestLogin(email)
        assertEquals(43, challenge.challengeId.length)
        assertEquals(600, challenge.expiresIn)
        assertNull(codes["login:$email"])
        assertNull(service.verifyLogin(RecoveryVerify(challenge.challengeId, "000000")))
    }

    @Test fun `purpose separation rejects registration and enrollment proofs for login`() {
        val f = fixture()
        val enroll = enrollment(f).second
        assertNull(service.verifyLogin(enroll))
        assertNull(service.verifyLogin(RecoveryVerify(AuthService.issueRegistrationToken(), enroll.otp)))
        assertTrue(service.verifyEnrollment(f.user, f.epoch, enroll))
        val login = service.requestLogin(f.email)
        assertFalse(service.verifyEnrollment(f.user, f.epoch, RecoveryVerify(login.challengeId, codes["login:${f.email}"]!!)))
    }

    @Test fun `concurrent guesses cannot exceed five attempts including malformed OTPs`() {
        val f = fixture(); bind(f)
        val challenge = service.requestLogin(f.email)
        val pool = Executors.newFixedThreadPool(8)
        try {
            pool.invokeAll((1..20).map { Callable { service.verifyLogin(RecoveryVerify(challenge.challengeId, "bad")) } }).forEach { assertNull(it.get()) }
        } finally { pool.shutdown() }
        assertNull(service.verifyLogin(RecoveryVerify(challenge.challengeId, codes["login:${f.email}"]!!)))
        Database.getConnection().use { connection ->
            connection.prepareStatement("SELECT attempts FROM account_recovery_challenges WHERE challenge_index = ?").use {
                it.setString(1, cipher.index("challenge-login", challenge.challengeId))
                it.executeQuery().use { rows -> assertTrue(rows.next()); assertEquals(5, rows.getInt(1)) }
            }
        }
    }

    @Test fun `fifth correct attempt succeeds and concurrent OTP consumption is single use`() {
        val f = fixture(); bind(f)
        val challenge = service.requestLogin(f.email)
        repeat(4) { assertNull(service.verifyLogin(RecoveryVerify(challenge.challengeId, "bad"))) }
        val request = RecoveryVerify(challenge.challengeId, codes["login:${f.email}"]!!)
        val pool = Executors.newFixedThreadPool(6)
        try {
            assertEquals(1, pool.invokeAll((1..6).map { Callable { service.verifyLogin(request) } }).count { it.get() != null })
        } finally { pool.shutdown() }
    }

    @Test fun `hourly email quota survives service recreation and remains generic`() {
        val f = fixture(); bind(f)
        repeat(5) { service.requestLogin(f.email) }
        val again = RecoveryAuthService(cipher) { _, _, _ -> fail<Unit>("Quota bypass") }
        val denied = again.requestLogin(f.email)
        assertEquals(600, denied.expiresIn)
        assertNull(again.verifyLogin(RecoveryVerify(denied.challengeId, codes["login:${f.email}"]!!)))
    }

    @Test fun `preserve rotates credentials and exact retries return identical token pair`() {
        val f = fixture(); bind(f)
        val oldAccess = AuthService.issueToken(f.user)
        val oldRefresh = AuthService.issueRefreshToken(f.user)
        val request = completion(f, grant(f))
        val result = service.complete(request)!!
        assertFalse(result.identityReplaced)
        assertEquals(f.user, AuthService.verifyToken(result.token))
        assertNull(AuthService.verifyToken(oldAccess))
        assertNull(AuthService.verifyRefreshToken(oldRefresh))
        assertEquals(result, service.complete(request))
        // Ayni cihazda kimlik korunarak yapilan kurtarma bildirim gondermez.
        assertFalse(codes.containsKey("$RECOVERED_NOTICE:${f.email}"))
        assertNull(service.complete(request.copy(completionId = RecoveryRecordCipher.opaque())))
        CredentialState.rotateCredentialEpoch(f.user)
        assertNull(service.complete(request))
    }

    @Test fun `parallel completion requests issue only one credential pair`() {
        val f = fixture(); bind(f)
        val request = completion(f, grant(f))
        val pool = Executors.newFixedThreadPool(6)
        try {
            val results = pool.invokeAll((1..6).map { Callable { service.complete(request) } }).map { it.get() }
            assertTrue(results.all { it != null })
            assertEquals(1, results.toSet().size)
        } finally { pool.shutdown() }
    }

    @Test fun `completion requires possession and preserve forbids key or registration mismatch`() {
        val f = fixture(); bind(f)
        val before = CredentialState.snapshot(f.user)!!.credentialEpoch
        assertNull(service.complete(completion(f, grant(f)).copy(signature = "invalid")))
        assertNull(service.complete(completion(f, grant(f), ed25519())))
        val badReg = completion(f, grant(f)).copy(registrationId = 5678)
        assertNull(service.complete(badReg.copy(signature = sign(f.key, RecoveryAuthService.completionPreimage(f.user, badReg)))))
        assertEquals(before, CredentialState.snapshot(f.user)!!.credentialEpoch)
    }

    // Test adi "both namespaces" idi; v2 prekey yolu kaldirildi ve artik tek
    // namespace var. Olculen asil ozellik degismedi ve kritik: kimlik
    // degistikten sonra ESKI epoch ile gelen yazmalar reddedilmeli. Bu
    // ozellik olmazsa kuyruga takilmis eski bir yazma kurtarilmis hesabin
    // anahtarlarini geri diker.
    @Test fun `replacement clears the pin and superseded uploads fail`() {
        val f = fixture(); bind(f)
        // libsignal bundle yolu kurtarma anahtarindan ayri bir 33 bayt kimlik
        // kullanir (fixture'in `identity_public_key` seed'iyle ayni).
        val libsignalIdentity = ByteArray(33) { it.toByte() }
        PreKeyStore.uploadBundle(f.user, libsignalIdentity, 1234,
            PreKeyStore.SignedPreKey(1, ByteArray(33), ByteArray(64)), listOf(PreKeyStore.OneTimePreKey(1, ByteArray(33))))
        val next = ed25519()
        val request = completion(f, grant(f), next, "replace", "olm")
        val response = service.complete(request)!!
        assertTrue(response.identityReplaced)
        // Hesap sahibi yeni cihazda kurtarmadan e-postayla haberdar edilir;
        // ayni istegin tekrari ikinci bildirim gondermez.
        assertTrue(codes.containsKey("$RECOVERED_NOTICE:${f.email}"))
        codes.remove("$RECOVERED_NOTICE:${f.email}")
        assertEquals(response, service.complete(request))
        assertFalse(codes.containsKey("$RECOVERED_NOTICE:${f.email}"))
        assertNull(PreKeyStore.fetchBundle(f.user))
        assertEquals(0, PreKeyStore.unconsumedCount(f.user))
        assertThrows(IllegalStateException::class.java) {
            PreKeyStore.setIdentityKey(f.user, libsignalIdentity, 1234)
        }
        assertThrows(IllegalStateException::class.java) {
            PreKeyStore.addOneTimePreKeys(f.user, listOf(PreKeyStore.OneTimePreKey(2, ByteArray(33))), f.epoch)
        }
        // Olm yolu da ayni cerceveye tabi olmali.
        assertThrows(IllegalStateException::class.java) {
            OlmPreKeyStore.addOneTimeKeys(
                f.user,
                listOf(OlmPreKeyStore.OneTimeKey("k1", ByteArray(32))),
                f.epoch,
            )
        }
        // Temiz kirilma: replace Olm kimligini + kurtarma pinini (signing_
        // public_key) NULL'a ceker. Yeni cihaz `publishIfNeeded` ile taze
        // kimligi yukleyene dek pin yoktur; bu nedenle yeni bir kurtarma
        // grant'i da (eski binding bayat + pin yok) mumkun degildir. O
        // yeniden-kurulum + yeniden-enroll akisi cihaz + deploy testinde
        // dogrulanacak; burada yalniz temizlemeyi olcuyoruz.
        assertNull(signingKey(f.user))
    }

    // Istemci artik libsignal bundle yuklemiyor; `registration_id` yalniz o
    // yukleme ile yazildigi icin Olm-only hesapta NULL. Eskiden 0 okunur ve
    // kurtarma hem istemcide (`reg < 1`) hem sunucuda (`!in 1..16383`)
    // reddedilirdi.
    private fun lockProof(seed: Int) = Base64.getEncoder().encodeToString(ByteArray(32) { (seed + it).toByte() })

    @Test fun `registration lock requires the PIN proof for a new device and can be retried`() {
        val f = fixture(); bind(f)
        assertEquals(false, service.registrationLockEnabled(f.user, f.epoch))
        assertTrue(service.updateRegistrationLock(f.user, f.epoch, lockProof(1)))
        assertEquals(true, service.registrationLockEnabled(f.user, f.epoch))
        // Eski epoch ile kilit degistirilemez.
        assertFalse(service.updateRegistrationLock(f.user, "stale-epoch", null))

        val grant = grant(f)
        assertTrue(grant.registrationLock)
        val request = completion(f, grant, ed25519(), "replace")
        val missing = assertThrows(RegistrationLockException::class.java) { service.complete(request) }
        assertEquals(RegistrationLock.Check.Failed(RegistrationLock.MAX_FAILURES - 1), missing.check)
        val wrong = assertThrows(RegistrationLockException::class.java) {
            service.complete(request.copy(lockProof = lockProof(2)))
        }
        assertEquals(RegistrationLock.Check.Failed(RegistrationLock.MAX_FAILURES - 2), wrong.check)
        // Ayni izinle dogru PIN kabul edilir; yanlis denemeler izni harcamaz.
        val recovered = service.complete(request.copy(lockProof = lockProof(1)))!!
        assertTrue(recovered.identityReplaced)
        assertTrue(codes.containsKey("$RECOVERED_NOTICE:${f.email}"))
    }

    @Test fun `registration lock locks recovery after too many wrong PINs`() {
        val f = fixture(); bind(f)
        assertTrue(service.updateRegistrationLock(f.user, f.epoch, lockProof(1)))
        val request = completion(f, grant(f), ed25519(), "replace")
        repeat(RegistrationLock.MAX_FAILURES - 1) {
            assertTrue(
                assertThrows(RegistrationLockException::class.java) {
                    service.complete(request.copy(lockProof = lockProof(9)))
                }.check is RegistrationLock.Check.Failed,
            )
        }
        val locked = assertThrows(RegistrationLockException::class.java) {
            service.complete(request.copy(lockProof = lockProof(9)))
        }.check
        assertTrue(locked is RegistrationLock.Check.Locked)
        // Kilit suresince dogru PIN de kabul edilmez.
        assertTrue(
            assertThrows(RegistrationLockException::class.java) {
                service.complete(request.copy(lockProof = lockProof(1)))
            }.check is RegistrationLock.Check.Locked,
        )
    }

    @Test fun `same-device recovery and a cleared lock need no PIN`() {
        val f = fixture(); bind(f)
        assertTrue(service.updateRegistrationLock(f.user, f.epoch, lockProof(1)))
        // Ayni cihaz (preserve) kimlik degistirmez; PIN istenmez.
        val preserved = service.complete(completion(f, grant(f)))!!
        assertFalse(preserved.identityReplaced)
        val epoch = CredentialState.snapshot(f.user)!!.credentialEpoch
        assertTrue(service.updateRegistrationLock(f.user, epoch, null))
        assertEquals(false, service.registrationLockEnabled(f.user, epoch))
        assertNotNull(service.complete(completion(f, grant(f), ed25519(), "replace")))
    }

    @Test fun `olm only account without registration id can still recover`() {
        val f = fixture()
        Database.getConnection().use { connection ->
            connection.prepareStatement("UPDATE users SET registration_id = NULL WHERE user_id = ?::uuid").use {
                it.setString(1, f.user); it.executeUpdate()
            }
        }
        bind(f)
        val grant = grant(f)
        assertEquals(RecoveryAuthService.OLM_RECOVERY_REGISTRATION_ID, grant.registrationId)
        val unsigned = RecoveryComplete(grant.recoveryToken, RecoveryRecordCipher.opaque(), "preserve", "olm",
            Base64.getEncoder().encodeToString(pub(f.key)), grant.registrationId, "")
        val request = unsigned.copy(signature = sign(f.key, RecoveryAuthService.completionPreimage(f.user, unsigned)))
        val response = service.complete(request)
        assertNotNull(response)
        assertFalse(response!!.identityReplaced)
    }

    @Test fun `competing capabilities become stale after one recovery`() {
        val f = fixture(); bind(f)
        val first = completion(f, grant(f))
        val second = completion(f, grant(f))
        assertNotNull(service.complete(first))
        assertNull(service.complete(second))
    }

    @Test fun `receipt storage failure rolls back credential rotation identity replacement and consumption`() {
        val f = fixture(); bind(f)
        val request = completion(f, grant(f), ed25519(), "replace")
        Database.getConnection().use { connection ->
            connection.createStatement().use { it.execute("ALTER TABLE account_recovery_receipts ADD CONSTRAINT recovery_test_failure CHECK (false) NOT VALID") }
        }
        try {
            assertThrows(java.sql.SQLException::class.java) { service.complete(request) }
            assertEquals(f.epoch, CredentialState.snapshot(f.user)!!.credentialEpoch)
            assertEquals(1, count("account_recovery_challenges", "challenge_index", cipher.index("challenge-complete", request.recoveryToken)))
        } finally {
            Database.getConnection().use { connection ->
                connection.createStatement().use { it.execute("ALTER TABLE account_recovery_receipts DROP CONSTRAINT recovery_test_failure") }
            }
        }
        assertNotNull(service.complete(request))
    }

    @Test fun `a login OTP expiring while queued on an account lock cannot verify`() {
        val f = fixture(); bind(f)
        val challenge = service.requestLogin(f.email)
        val pool = Executors.newSingleThreadExecutor()
        try {
            Database.getConnection().use { blocker ->
                blocker.autoCommit = false
                blocker.prepareStatement("SELECT user_id FROM users WHERE user_id = ?::uuid FOR UPDATE").use {
                    it.setString(1, f.user); it.executeQuery().close()
                }
                Database.getConnection().use { connection ->
                    connection.prepareStatement("UPDATE account_recovery_challenges SET expires_at = clock_timestamp() + INTERVAL '1 second' WHERE challenge_index = ?").use {
                        it.setString(1, cipher.index("challenge-login", challenge.challengeId)); it.executeUpdate()
                    }
                }
                val future = pool.submit(Callable { service.verifyLogin(RecoveryVerify(challenge.challengeId, codes["login:${f.email}"]!!)) })
                val deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(5)
                var waiting = false
                while (!waiting && System.nanoTime() < deadline) {
                    Database.getConnection().use { connection ->
                        connection.createStatement().use { statement ->
                            statement.executeQuery("SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock')").use {
                                it.next(); waiting = it.getBoolean(1)
                            }
                        }
                    }
                    if (!waiting) Thread.sleep(10)
                }
                assertTrue(waiting)
                Thread.sleep(1100)
                blocker.commit()
                assertNull(future.get(5, java.util.concurrent.TimeUnit.SECONDS))
            }
        } finally { pool.shutdownNow() }
    }

    @Test fun `protected schema contains no plaintext account or email and deletion removes binding challenges receipts`() {
        val f = fixture(); bind(f)
        service.complete(completion(f, grant(f)))!!
        service.requestLogin(f.email)
        val ai = cipher.index("account", f.user)
        Database.getConnection().use { connection ->
            connection.createStatement().use { statement ->
                statement.executeQuery("SELECT row_to_json(b)::text FROM account_recovery_bindings b").use { rows ->
                    while (rows.next()) { assertFalse(rows.getString(1).contains(f.email)); assertFalse(rows.getString(1).contains(f.user)) }
                }
            }
        }
        assertTrue(AccountDeletion.deleteDurableState(f.user))
        for (table in listOf("account_recovery_bindings", "account_recovery_challenges", "account_recovery_receipts")) {
            assertEquals(0, count(table, "account_index", ai))
        }
    }

    @Test fun `expiry rejects challenges and receipts and retention removes all transient rows`() {
        val f = fixture(); bind(f)
        val request = completion(f, grant(f))
        service.complete(request)!!
        val challenge = service.requestLogin(f.email)
        Database.getConnection().use { connection ->
            for (table in listOf("account_recovery_challenges", "account_recovery_quotas", "account_recovery_receipts")) {
                connection.createStatement().use { it.executeUpdate("UPDATE $table SET expires_at = NOW() - INTERVAL '1 second'") }
            }
            assertNull(service.complete(request))
            assertNull(service.verifyLogin(RecoveryVerify(challenge.challengeId, codes["login:${f.email}"]!!)))
            AccountRecovery.purgeExpired(connection)
            for (table in listOf("account_recovery_challenges", "account_recovery_quotas", "account_recovery_receipts")) {
                connection.createStatement().use { it.executeQuery("SELECT COUNT(*) FROM $table").use { rows -> rows.next(); assertEquals(0, rows.getInt(1)) } }
            }
        }
    }
}
