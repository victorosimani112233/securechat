package com.securechat.botadmin.commands

import com.github.ajalt.clikt.core.CliktCommand
import com.securechat.botadmin.buildAdminClient
import kotlin.system.exitProcess

class EmergencyStopCommand : CliktCommand(
    name = "emergency-stop",
    help = "Tum send isteklerini durdur (503 dondurur)"
) {
    override fun run() {
        val resp = buildAdminClient().post("/admin/emergency/stop", "{}")
        if (!resp.isOk) {
            System.err.println("Hata HTTP ${resp.code}: ${resp.body}")
            exitProcess(1)
        }
        println("Emergency STOP aktif")
        println(resp.body)
    }
}

class EmergencyResumeCommand : CliktCommand(
    name = "emergency-resume",
    help = "Send isteklerini tekrar etkinlestir"
) {
    override fun run() {
        val resp = buildAdminClient().post("/admin/emergency/resume", "{}")
        if (!resp.isOk) {
            System.err.println("Hata HTTP ${resp.code}: ${resp.body}")
            exitProcess(1)
        }
        println("Emergency RESUME — send istekleri tekrar isleniyor")
        println(resp.body)
    }
}

class EmergencyStatusCommand : CliktCommand(
    name = "emergency-status",
    help = "Emergency stop durumunu sorgula"
) {
    override fun run() {
        val resp = buildAdminClient().get("/admin/emergency/status")
        if (!resp.isOk) {
            System.err.println("Hata HTTP ${resp.code}: ${resp.body}")
            exitProcess(1)
        }
        println(resp.body)
    }
}
