package com.securechat.signaling

/**
 * WebSocket handshake'inde kabul edilen tek credential tasiyicisi.
 *
 * Query string; reverse proxy, WAF, load balancer, APM ve hata telemetrisi
 * tarafindan rutin olarak kaydedilir. Container log driver'ini kapatmak host
 * tarafindaki bu kopyalari korumaz. Bu yuzden access token URL'de tasinamaz;
 * yalniz `Authorization: Bearer` kabul edilir.
 *
 * Query'de token gorulmesi sessizce yok sayilmaz: o token artik loglanmis
 * kabul edilir ve baglanti fail-closed reddedilir; boylece bir istemci
 * regresyonu sessizce credential sizdirmaya devam edemez.
 */
object WebSocketCredentials {

    private const val BEARER_PREFIX = "Bearer "

    sealed interface Result {
        /** Header'dan alinmis, bicimi gecerli bearer token. */
        data class Accepted(val token: String) : Result

        /** Hicbir credential sunulmadi. */
        data object Missing : Result

        /** Token query string'inde tasinmis; baglanti reddedilir. */
        data object TokenInQuery : Result

        /** Authorization header'i var fakat bearer semasi disinda. */
        data object MalformedHeader : Result
    }

    fun extract(authorizationHeader: String?, queryToken: String?): Result {
        if (!queryToken.isNullOrBlank()) return Result.TokenInQuery
        val header = authorizationHeader?.trim()
        if (header.isNullOrEmpty()) return Result.Missing
        if (!header.startsWith(BEARER_PREFIX)) return Result.MalformedHeader
        val token = header.removePrefix(BEARER_PREFIX).trim()
        if (token.isEmpty()) return Result.MalformedHeader
        return Result.Accepted(token)
    }
}
