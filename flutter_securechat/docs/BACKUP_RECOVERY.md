# History backup and account recovery

Backups are password-encrypted history archives, not authentication or device
transfer credentials. Recover/authenticate the account separately before
restoring history on a recovered device.

## Account binding

- Profiles must carry a syntactically valid UUID. An existing local UUID must
  match exactly, including when the local profile is offline. Matching phone
  numbers do not establish ownership; a changed phone does not invalidate the
  same authenticated UUID.
- Authenticated restore keeps the entire current profile and credential pair.
  Old display names, phone numbers, photos, and injected credentials are ignored.
- Offline restore supports v1 Kotlin and v2/v3 Flutter archives with valid UUIDs.
  It installs profile/history without logging in. Missing optional display,
  phone, and photo fields default to empty; non-null non-string values fail.
  Legacy phone-only, missing/blank/non-UUID profiles are rejected before writes.
- Partial/orphan access or refresh credentials cannot be attached to an imported
  profile. Account identity/login state is checked again in the database write
  queue immediately before replacement.

## Local Security State

`replaceFromPortableJson(..., preserveLocalSecurityState: true)` copies the
current `identities`, `preKeys`, `signedPreKeys`, `sessions`, `senderKeys`,
`pendingSignals`, and entire `cryptoState` map inside the serialized write
operation. This retains peer verification pins, recovered private keys,
registration ID, staged recovery records, ratchets, pending ciphertext,
rotation/replay state, lock credentials, and other backup attempt counters.
Queued protocol writes are not overwritten by an earlier exported snapshot.
The ordinary replacement API defaults to its previous full-replacement behavior.

Both backup export and import use an explicit history collection allowlist.
All security collections and the whole generic `cryptoState` map are excluded,
including unknown future entries. In particular, backup settings formerly
passed through `cryptoState` no longer transfer. Only the fixed four profile
fields are exported; tokens are never exported or installed from a backup.
Portable JSON remains unencrypted in memory until compression/encryption and
is never written as a plaintext intermediate file.

History replacement is atomic in the encrypted database; malformed profiles,
versions, collection shapes, and database rows are rejected before replacement.
Persistence failure rolls the replacement back, retaining the live security
state in memory and on disk. The matching password-attempt marker is removed
after success; other local markers survive.

## Limits

An offline backup UUID is not server-authenticated evidence of ownership.
Offline profile persistence and database replacement remain separate writes;
a profile-file failure can leave restored history without a persisted profile.
Such a failure is reported, not treated as successful login. Authenticated
restore does not write the session file at all. The auth/lifecycle coordinator
must still serialize account changes with restore; this is not a global
cross-store transaction or a network/Signal processing pause.

Restoration replaces local history rather than merging it. Media paths retain
the existing portable format behavior; this change does not transfer local
media files or recover missing historical Signal keys.

## Verification

```sh
/home/user497/flutter/bin/flutter test --no-pub test/backup_module_test.dart test/backup_restore_persistence_test.dart test/backup_recovery_test.dart test/backup_password_dialog_test.dart
/home/user497/flutter/bin/dart analyze lib/src/backup/backup_service.dart test/backup_module_test.dart test/backup_restore_persistence_test.dart test/backup_recovery_test.dart
```

The recovery tests use the real encrypted database and persistent session store,
including close/reopen assertions, unchanged file bytes on rejected input,
transaction failure injection, queued security writes, and authenticated export
inspection. Cryptographic record fixtures assert byte/trust preservation; they
do not replace the separate Signal interoperability tests.
