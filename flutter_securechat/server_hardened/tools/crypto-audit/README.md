# Crypto Audit Inputs

The files under `vectors/` are pinned Google Wycheproof test vectors from the
official C2SP repository at commit:

`dac1dd4729fd1f8dd9e1e9f3dce51d783da6c166`

Verify them offline from this directory with:

```bash
sha256sum --check SHA256SUMS
```

`WycheproofKatTest` checks AES-256-GCM with the application's production
parameters (256-bit key, 96-bit nonce, 128-bit tag), Ed25519 verification,
HMAC-SHA1, and HMAC-SHA256 against the active JCA provider. Wycheproof has no
vector for SecureChat's custom raw-RSA OPRF; that protocol requires the
separate Kotlin/Flutter cross-language KAT and external protocol review.

`oprf_cross_language_kat.json` was generated once by
`generate_oprf_kat.py` using Python `cryptography` for RSA key generation and
Python's independent big-integer/hash implementation for every protocol step.
The committed vector contains a test-only private key and must never be used
outside tests.

CryptoGuard is intentionally not made a release gate: its official release
requires JDK 8 and cannot reliably load this Java 17 bytecode. CogniCrypt may
be used as an advisory scan only after its SARIF output has a reviewed,
versioned baseline; its stock JCA rules do not currently model Ed25519 used by
this codebase without false positives.

The reviewed CogniCrypt 5.0.1 inputs are:

```text
177cefb7939c558837051f96705e240df9c43b44a037e4bf8e0da266f406a1b9  HeadlessJavaScanner-5.0.1-jar-with-dependencies.jar
d6dce41385627bdcb7c57a9a578636f7a945b327c52ed1433e5733981e6333ff  JavaCryptographicArchitecture.zip
```

Place those two files in a directory outside the repository, set
`CRYPTO_AUDIT_TOOL_DIR`, and run `run_cognicrypt_advisory.sh`. The script
verifies both hashes before execution. It deliberately does not turn the raw
finding count into a pass/fail result: CogniCrypt exits zero with findings and
the stock rules report expected false positives for Ed25519, externally loaded
AES/HMAC keys, the protocol-required coturn HMAC-SHA1 use, and raw RSA group
operations.
