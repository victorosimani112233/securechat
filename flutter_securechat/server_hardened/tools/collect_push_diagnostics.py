#!/usr/bin/env python3
"""Read only local, authenticated, identity-free push diagnostics."""

import http.client
import json
import math
import os
from pathlib import Path
import re
import sys


STAGES = frozenset({
    "registration_hinted", "registration_keyless", "wake_not_operational",
    "wake_registration_unavailable", "wake_lookup_failed", "wake_rate_limited",
    "wake_hint_missing", "wake_accepted_hinted", "wake_accepted_keyless", "wake_failed",
})
METRIC = re.compile(r'^securechat_fcm_diagnostic_total\{stage="([a-z_]+)",?\} ([0-9.eE+\-]+)$')
MAX_RESPONSE = 1024 * 1024


def read_token():
    path = os.environ.get("METRICS_BEARER_TOKEN_FILE")
    token = Path(path).read_text().strip() if path else os.environ.get("METRICS_BEARER_TOKEN", "")
    if len(token) < 32 or "\r" in token or "\n" in token:
        raise ValueError("Metrics credential missing or invalid; load the existing server environment")
    return token


def fetch(port, path, token):
    # No proxy, redirect, remote destination, argv token or temporary credential file.
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    try:
        connection.request("GET", path, headers={"Authorization": "Bearer " + token})
        response = connection.getresponse()
        if response.status != 200:
            raise RuntimeError("Local diagnostics endpoint returned HTTP " + str(response.status))
        data = response.read(MAX_RESPONSE + 1)
        if len(data) > MAX_RESPONSE:
            raise ValueError("Diagnostics response exceeds size limit")
        return data.decode("utf-8")
    finally:
        connection.close()


def parse_counters(text):
    result = {}
    for line in text.splitlines():
        match = METRIC.fullmatch(line)
        if not match or match[1] not in STAGES:
            continue
        value = float(match[2])
        if not math.isfinite(value) or value < 0 or match[1] in result:
            raise ValueError("Invalid diagnostic counter")
        result[match[1]] = value
    if result.keys() != STAGES:
        raise ValueError("Push diagnostic counters absent; verify the running JAR and port")
    return result


def main():
    try:
        port = int(os.environ.get("PORT", "8080"))
        if not 1 <= port <= 65535:
            raise ValueError("Invalid local server port")
        token = read_token()
        version = json.loads(fetch(port, "/api/v1/version", token))
        counters = parse_counters(fetch(port, "/metrics", token))
        print(json.dumps({
            "build": {key: version.get(key) for key in ("commit", "builtAt", "migrationTarget")},
            "pushCounters": counters,
        }, indent=2, sort_keys=True))
        return 0
    except Exception as error:
        # Never print response bodies, credentials, environment or exception text.
        print("Push diagnostics failed (" + type(error).__name__ +
              "). Check server port, existing metrics credential and JAR version.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
