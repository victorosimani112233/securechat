package com.securechat.botadmin

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.subcommands
import com.securechat.botadmin.commands.ClientCommand
import com.securechat.botadmin.commands.EmergencyResumeCommand
import com.securechat.botadmin.commands.EmergencyStatusCommand
import com.securechat.botadmin.commands.EmergencyStopCommand

/**
 * bot-admin CLI giris noktasi.
 *
 * Kullanim:
 *   bot-admin client add --name X --pubkey-file pub --allow user:UUID --rate 50
 *   bot-admin client list
 *   bot-admin client revoke <kid> [--reason TEXT]
 *   bot-admin client rotate <kid> --new-pubkey-file new.pub
 *   bot-admin emergency-stop
 *   bot-admin emergency-resume
 *   bot-admin emergency-status
 *
 * Env:
 *   BOT_ADMIN_TOKEN     — zorunlu, X-Admin-Token degeri
 *   BOT_ADMIN_SOCKET    — Unix socket path (varsa kullanilir)
 *   BOT_ADMIN_URL       — TCP fallback (default: http://127.0.0.1:8092)
 */
class BotAdminCli : CliktCommand(
    name = "bot-admin",
    help = "SecureChat Bot API admin yonetim aracı"
) {
    override fun run() = Unit
}

fun main(args: Array<String>) {
    BotAdminCli()
        .subcommands(
            ClientCommand(),
            EmergencyStopCommand(),
            EmergencyResumeCommand(),
            EmergencyStatusCommand()
        )
        .main(args)
}
