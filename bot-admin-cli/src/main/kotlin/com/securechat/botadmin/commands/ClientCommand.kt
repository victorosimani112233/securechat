package com.securechat.botadmin.commands

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.clikt.parameters.arguments.argument
import com.github.ajalt.clikt.parameters.options.flag
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.options.required
import com.github.ajalt.clikt.parameters.types.file
import com.github.ajalt.clikt.parameters.types.int
import com.github.ajalt.clikt.parameters.types.long
import com.securechat.botadmin.buildAdminClient
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.MessageDigest
import java.util.Base64
import kotlin.system.exitProcess

private val json = Json { ignoreUnknownKeys = true }

class ClientCommand : CliktCommand(name = "client", help = "API client'larini yonet") {
    init { subcommands(ClientAdd(), ClientList(), ClientRevoke(), ClientRotate()) }
    override fun run() = Unit
}

class ClientAdd : CliktCommand(name = "add", help = "Yeni API client ekle") {
    private val name by option("--name", help = "Client adi (zorunlu)").required()
    private val pubkeyFile by option("--pubkey-file", help = "Public key dosyasi (base64 32 byte)")
        .file(mustExist = true).required()
    private val allow by option(
        "--allow",
        help = "Allow-list virgulle ayri: user:UUID,group:ID,user:UUID"
    ).required()
    private val rate by option("--rate-per-hour", help = "Saatlik limit (default 50)").int()
    private val perRecipient by option("--per-recipient-per-day", help = "Recipient/gun limit").int()
    private val expiresInDays by option("--expires-in-days", help = "Suresi (gun)").long()
    private val showFingerprint by option("--show-fingerprint").flag()

    override fun run() {
        val rawKey = pubkeyFile.readText().trim()
        val pubBytes = decodePubKey(rawKey)
        if (showFingerprint) {
            println("Fingerprint (SHA-256/base64url): " + fingerprint(pubBytes))
        }
        require(pubBytes.size == 32) { "Public key 32 byte olmali (mevcut: ${pubBytes.size})" }

        val req = AddRequest(
            name = name,
            publicKey = Base64.getEncoder().encodeToString(pubBytes),
            allowList = allow.split(",").map { it.trim() }.filter { it.isNotEmpty() },
            ratePerHour = rate,
            perRecipientPerDay = perRecipient,
            expiresInDays = expiresInDays
        )
        val client = buildAdminClient()
        val resp = client.post("/admin/clients", json.encodeToString(req))
        if (!resp.isOk) {
            System.err.println("Hata HTTP ${resp.code}: ${resp.body}")
            exitProcess(1)
        }
        println(resp.body)
    }

    @Serializable
    private data class AddRequest(
        val name: String,
        val publicKey: String,
        val allowList: List<String>,
        val ratePerHour: Int? = null,
        val perRecipientPerDay: Int? = null,
        val expiresInDays: Long? = null
    )
}

class ClientList : CliktCommand(name = "list", help = "Tum client'lari listele") {
    override fun run() {
        val resp = buildAdminClient().get("/admin/clients")
        if (!resp.isOk) {
            System.err.println("Hata HTTP ${resp.code}: ${resp.body}")
            exitProcess(1)
        }
        println(resp.body)
    }
}

class ClientRevoke : CliktCommand(name = "revoke", help = "Client'i revoke et (anlik)") {
    private val kid by argument(help = "Hedef kid")
    private val reason by option("--reason")

    override fun run() {
        val path = "/admin/clients/$kid" + (reason?.let { "?reason=${urlEnc(it)}" } ?: "")
        val resp = buildAdminClient().delete(path)
        if (!resp.isOk) {
            System.err.println("Hata HTTP ${resp.code}: ${resp.body}")
            exitProcess(1)
        }
        println(resp.body)
    }

    private fun urlEnc(s: String) = java.net.URLEncoder.encode(s, Charsets.UTF_8)
}

class ClientRotate : CliktCommand(name = "rotate", help = "Eski kid'i revoke + yeni client uret") {
    private val kid by argument(help = "Mevcut kid")
    private val newPubkeyFile by option("--new-pubkey-file")
        .file(mustExist = true).required()

    override fun run() {
        val rawKey = newPubkeyFile.readText().trim()
        val pubBytes = decodePubKey(rawKey)
        require(pubBytes.size == 32) { "Yeni public key 32 byte olmali" }
        val req = RotateRequest(newPublicKey = Base64.getEncoder().encodeToString(pubBytes))
        val resp = buildAdminClient().post("/admin/clients/$kid/rotate", json.encodeToString(req))
        if (!resp.isOk) {
            System.err.println("Hata HTTP ${resp.code}: ${resp.body}")
            exitProcess(1)
        }
        println(resp.body)
    }

    @Serializable
    private data class RotateRequest(val newPublicKey: String)
}

// --- yardimcilar ---

private fun decodePubKey(s: String): ByteArray {
    val trimmed = s.trim().lines().last { it.isNotBlank() }  // ssh-keygen output ilk satir basligini atla
        .let { line ->
            // "ssh-ed25519 AAAA... comment" formatinda 2. token alanini al
            val tokens = line.split(Regex("\\s+"))
            when {
                tokens.size >= 2 && tokens[0].startsWith("ssh-") -> tokens[1]
                else -> line
            }
        }
    val decoded = try {
        Base64.getDecoder().decode(trimmed)
    } catch (e: Exception) {
        Base64.getUrlDecoder().decode(trimmed)
    }
    // ssh-ed25519 formatinda decoded blob "openssh wire" formatinda: prefix + algo + pubkey.
    // Sadece son 32 byte raw ed25519 pubkey.
    return if (decoded.size > 32 && decoded.size <= 64) {
        decoded.takeLast(32).toByteArray()
    } else {
        decoded
    }
}

private fun fingerprint(pubBytes: ByteArray): String {
    val sha = MessageDigest.getInstance("SHA-256").digest(pubBytes)
    return Base64.getUrlEncoder().withoutPadding().encodeToString(sha)
}
