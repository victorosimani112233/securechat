package com.securechat.signaling

import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.createApplicationPlugin
import io.ktor.server.application.hooks.CallSetup

/**
 * Butun yanitlara sabit guvenlik basliklarini ekler.
 *
 * Harici bir tarama (strix) bu basliklarin eksikligini defense-in-depth
 * bulgusu olarak isaretledi. Bir JSON/WebSocket API tarayici tarafindan
 * dogrudan render edilmese de:
 *
 *  - `no-store`, TURN kimlik bilgileri ve rehber snapshot'i gibi hassas
 *    yanitlarin ara proxy'lerde onbelleklenmesini engeller;
 *  - `nosniff` + `frame-ancestors 'none'`, ileride bir web yuzeyi eklenirse
 *    MIME-sniffing ve clickjacking'i kapatir;
 *  - `Referrer-Policy: no-referrer`, URL'lerin ucuncu taraflara sizmasini
 *    onler.
 *
 * Basliklar cagri isleyicisinden **once** eklenir; bir isleyici gerekirse
 * ustune yazabilir.
 */
val SecurityHeaders = createApplicationPlugin(name = "SecurityHeaders") {
    on(CallSetup) { call ->
        applySecurityHeaders(call)
    }
}

/** İsim -> deger; sabit, her yanitta ayni. Test bu listeye karsi dogrular. */
internal val SECURITY_HEADERS: List<Pair<String, String>> = listOf(
    "X-Content-Type-Options" to "nosniff",
    "X-Frame-Options" to "DENY",
    "Content-Security-Policy" to "default-src 'none'; frame-ancestors 'none'",
    "Referrer-Policy" to "no-referrer",
    // Bu bir API'dir; hicbir yaniti onbelleklenmemelidir. Hassas yanitlar
    // (ice/config TURN kimlikleri, directory/snapshot) icin zorunlu, digerleri
    // icin zararsizdir.
    "Cache-Control" to "no-store",
    // Tamamlayici izolasyon basliklari (deep-scan bulgu). JSON/WS API icin
    // pratik etkisi sinirli ama prod-hazirligi ve derinlik icin eklenir.
    "Permissions-Policy" to "geolocation=(), microphone=(), camera=(), payment=()",
    "Cross-Origin-Opener-Policy" to "same-origin",
    "Cross-Origin-Embedder-Policy" to "require-corp",
    "Cross-Origin-Resource-Policy" to "same-origin",
    "X-Permitted-Cross-Domain-Policies" to "none",
)

internal fun applySecurityHeaders(call: ApplicationCall) {
    for ((name, value) in SECURITY_HEADERS) {
        if (call.response.headers[name] == null) {
            call.response.headers.append(name, value, safeOnly = false)
        }
    }
}
