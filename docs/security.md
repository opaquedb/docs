# Security

OpaqueDB is a privacy system. All client-supplied bytes (ciphertexts, keys, SQL
templates, parameters) and all on-disk bytes (manifests, segments, WAL) are
treated as untrusted.

## Trust model

- Privacy holds against a **semi-honest operator**. There is no non-collusion
  assumption between servers, so the whole cluster is a single trust domain.
- The system is **QueryPrivate**: the operator never learns the query value or
  the secret key. DataPrivate mode, where the operator also never learns the
  stored data, is a later release.
- **Authentication is access control, not anonymity.** The operator may learn
  which principal queried; it must never see the query value. Client anonymity
  is a layer you add above the database.

## Hard constraints

These are enforced throughout the codebase:

- **Validate every size and bound before use.** Never index, allocate, mmap, or
  copy based on a length from input or a file without checking it against the
  actual available bytes. Use checked arithmetic for size math; never let
  `count * stride` wrap.
- **Validate client SEAL ciphertexts and keys** against the expected parameters
  (`parms_id`, sizes) before use. `DeserializeCiphertexts` does this per
  ciphertext. Reject malformed input with a status; do not crash.
- **No memory-safety bugs.** No OOB reads or writes, no use-after-free, no
  unchecked `reinterpret_cast` over input, no raw `memcpy` without a verified
  length. Prefer spans with explicit bounds and RAII for every resource.
- **mmap only immutable, published, read-only epoch snapshots.** Never mmap a
  path that can be written concurrently. The mmap reader validates the mapped
  length against the manifest before exposing any record. Segments are a 64-byte
  header plus fixed records, CRC32-checked. The WAL is length-and-CRC framed and
  replays only its valid prefix (torn-tail safe).
- **Never log** secret key material, plaintext query values, or auth tokens.
- **Compare auth tokens in constant time.** Secret files are readable only by the
  service user (0640 or stricter).

## Authentication

`Authenticator` supports `token`, `mtls`, and `none` modes and is gRPC-free. The
gRPC edge extracts a bearer token and the mTLS peer identity into
`auth::AuthInputs`. `RequestGate` runs auth then rate-limit on every query RPC.

!!! note "libsodium is deliberately absent"
    The node does not link libsodium. SEAL plus gRPC's OpenSSL plus libsodium
    triggers a symbol conflict that smashes the stack guard ("stack smashing
    detected" inside unrelated SEAL code). The `auth` layer compares
    high-entropy bearer tokens in constant time with no crypto library.

## Cluster security

Node-to-node traffic is a separate trust domain. Peer channels present the
cluster certificate and verify peers against the cluster CA. A clustered node
refuses to start without cluster mTLS or server TLS, unless
`cluster.allow_insecure` is set for local dev. See [Cluster](cluster.md).

## Empty results

A no-match query returns an encrypted empty result. The backend appends a
presence ciphertext (the match count); the client reads it first and returns
nothing at zero. The operator never learns whether a query matched.
