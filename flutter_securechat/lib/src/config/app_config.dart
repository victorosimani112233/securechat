class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.signalingUrl,
    required this.certificatePinHost,
    required this.certificatePins,
  });

  final String apiBaseUrl;
  final String signalingUrl;
  final String certificatePinHost;
  final List<String> certificatePins;

  /// ADB reverse exposes a host service through device loopback without
  /// creating an Android Wi-Fi/mobile transport. This exception is strictly
  /// debug-only and only applies when every configured endpoint is loopback.
  bool get allowsDebugLoopbackTransport {
    if (const bool.fromEnvironment('dart.vm.product')) return false;
    final endpoints = [Uri.parse(apiBaseUrl), Uri.parse(signalingUrl)];
    return endpoints.every((endpoint) => _isLoopbackHost(endpoint.host));
  }

  void validateNetworkSecurity() {
    final endpoints = [Uri.parse(apiBaseUrl), Uri.parse(signalingUrl)];
    if (const bool.fromEnvironment('dart.vm.product') &&
        (endpoints[0].scheme != 'https' || endpoints[1].scheme != 'wss')) {
      throw StateError(
        'Release derlemelerinde yalniz HTTPS/WSS kullanilabilir.',
      );
    }
    final tlsHosts = endpoints
        .where((uri) => uri.scheme == 'https' || uri.scheme == 'wss')
        .map((uri) => uri.host.toLowerCase())
        .toSet();
    if (tlsHosts.isEmpty) return;
    final host = certificatePinHost.trim().toLowerCase();
    if (host.isEmpty || certificatePins.length < 2) {
      throw StateError(
        'TLS endpointleri için birincil ve yedek SPKI pin zorunludur.',
      );
    }
    if (!tlsHosts.every((endpoint) => endpoint == host)) {
      throw StateError(
        'TLS endpoint hostları certificate pin hostuyla eşleşmiyor.',
      );
    }
  }

  static const current = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'SECURECHAT_API_BASE_URL',
      defaultValue: 'https://94.73.180.226',
    ),
    signalingUrl: String.fromEnvironment(
      'SECURECHAT_SIGNALING_URL',
      defaultValue: 'wss://94.73.180.226',
    ),
    certificatePinHost: String.fromEnvironment(
      'SECURECHAT_CERT_PIN_HOST',
      defaultValue: '94.73.180.226',
    ),
    certificatePins: [
      String.fromEnvironment(
        'SECURECHAT_CERT_PIN_SHA256',
        defaultValue: 'DLws9D1beDKBVkETgqo4rb0U9qXZx+AUVGKwaDXQiSA=',
      ),
      String.fromEnvironment(
        'SECURECHAT_CERT_PIN_SHA256_BACKUP',
        defaultValue: '4oaRg+Six29KZ2tcFLyoYT+FKUZhYPzp1pI5BoK5RI4=',
      ),
    ],
  );

  static bool _isLoopbackHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == 'localhost';
  }
}
