#!/usr/bin/env python3
"""Generate the independent test-only RSA-OPRF cross-language KAT."""

import base64
import hashlib
import json
import math
import struct
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


PHONE_DOMAIN = b"elcim-directory-phone-v1\x00"
TOKEN_DOMAIN = b"elcim-directory-token-v1\x00"


def b64u(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def width(value: int, size: int) -> bytes:
    return value.to_bytes(size, "big")


def full_domain_point(phone_hash: str, modulus: int, modulus_bytes: int) -> int:
    for attempt in range(256):
        seed = hashlib.sha256(
            PHONE_DOMAIN + phone_hash.encode("ascii") + struct.pack(">I", attempt)
        ).digest()
        expanded = bytearray()
        counter = 0
        while len(expanded) < modulus_bytes + 16:
            expanded.extend(hashlib.sha256(seed + struct.pack(">I", counter)).digest())
            counter += 1
        candidate = int.from_bytes(expanded, "big") % (modulus - 1) + 1
        if candidate > 1 and math.gcd(candidate, modulus) == 1:
            return candidate
    raise RuntimeError("hash-to-group failed")


def main() -> None:
    key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    private = key.private_numbers()
    public = private.public_numbers
    modulus = public.n
    exponent = public.e
    modulus_bytes = (modulus.bit_length() + 7) // 8
    phone_hash = hashlib.sha256(b"securechat-oprf-kat-phone-v1").hexdigest()
    point = full_domain_point(phone_hash, modulus, modulus_bytes)

    factor_seed = hashlib.sha512(b"securechat-oprf-kat-factor-v1").digest()
    factor = int.from_bytes(factor_seed, "big") % (modulus - 3) + 2
    while math.gcd(factor, modulus) != 1:
        factor += 1

    blinded = point * pow(factor, exponent, modulus) % modulus
    evaluated = pow(blinded, private.d, modulus)
    unblinded = evaluated * pow(factor, -1, modulus) % modulus
    direct = pow(point, private.d, modulus)
    assert unblinded == direct
    token = hashlib.sha256(TOKEN_DOMAIN + width(unblinded, modulus_bytes)).digest()

    private_der = key.private_bytes(
        serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    public_der = key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    result = {
        "generator": "python-cryptography-independent-v1",
        "protocolVersion": "elcim-directory-oprf-v1",
        "phoneHash": phone_hash,
        "privateKeyPkcs8": base64.b64encode(private_der).decode("ascii"),
        "keyId": b64u(hashlib.sha256(public_der).digest()),
        "modulus": b64u(width(modulus, modulus_bytes)),
        "exponent": b64u(exponent.to_bytes((exponent.bit_length() + 7) // 8, "big")),
        "point": b64u(width(point, modulus_bytes)),
        "factor": b64u(width(factor, modulus_bytes)),
        "blinded": b64u(width(blinded, modulus_bytes)),
        "evaluated": b64u(width(evaluated, modulus_bytes)),
        "unblinded": b64u(width(unblinded, modulus_bytes)),
        "token": b64u(token),
    }
    json.dump(result, sys.stdout, sort_keys=True, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
