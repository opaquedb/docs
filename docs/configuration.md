# Configuration

The `Config` struct is the only place settings live. They resolve once into a
single immutable `Config` that is injected everywhere.

## Resolution order

Later layers override earlier ones:

1. Built-in defaults.
2. The config file.
3. Environment variables, `OPAQUEDB_<SECTION>_<KEY>`.
4. Command-line flags (`--set section.key=value`).

Every setting is configurable through all four layers. The built-in defaults
live in one file, `config/opaquedb.default.toml`, embedded at build time.
`config init` writes it verbatim.

## Sections

### `[node]`

| Key | Default | Notes |
| --- | --- | --- |
| `id` | `""` | Empty means generate a stable random id. |
| `data_dir` | `/var/lib/opaquedb` | Root for stored data. |

### `[cluster]`

| Key | Default | Notes |
| --- | --- | --- |
| `enabled` | `false` | `true` to join an etcd cluster. |
| `etcd_endpoints` | `["http://127.0.0.1:2379"]` | |
| `leader_key` | `/opaquedb/leader` | |
| `etcd_username` / `etcd_password` | `""` | etcd password auth. |
| `etcd_ca_cert` | `""` | Connect to etcd over TLS. |
| `etcd_client_cert` / `etcd_client_key` | `""` | Mutual TLS to etcd. |
| `etcd_tls_name` | `""` | Certificate host name override when dialing by IP. |
| `tls_cert` / `tls_key` / `ca_cert` | `""` | Node-to-node mTLS, a separate trust domain. |
| `allow_insecure` | `false` | Permit unencrypted node-to-node RPC. Local dev only. |

TLS takes precedence if both etcd password and TLS settings are present. A
clustered node (`enabled = true`) must set the node-to-node `tls_cert`/`tls_key`/
`ca_cert` (or server TLS) or it refuses to start, unless `allow_insecure` is set.

### `[server]`

| Key | Default | Notes |
| --- | --- | --- |
| `listen` | `0.0.0.0:50051` | |
| `advertise` | `""` | Address peers use; required for clustering and when binding a wildcard. |
| `max_message_bytes` | `67108864` | Large enough for evaluation key streams. |
| `tls_cert` / `tls_key` | `""` | Required when `auth.mode = mtls`. |

### `[crypto]`

The single source of truth for FHE parameters. See
[How it works](how-it-works.md#fhe-parameters) for why these values.

| Key | Default | Notes |
| --- | --- | --- |
| `poly_modulus_degree` | `16384` | Power of two. Required at this value. |
| `plain_modulus_bits` | `20` | |
| `coeff_modulus_bits` | `[60, 60, 60, 60, 60, 49]` | 349 bits. |
| `key_bits` | `16` | Key universe `2^key_bits`; equality depth `1 + log2`. |

### `[storage]`

| Key | Default | Notes |
| --- | --- | --- |
| `record_bytes` | `128` | Fixed payload record size; sets the plane count. |
| `epoch_dir` | `""` | Empty means `data_dir/epochs`. |

### `[auth]`

| Key | Default | Notes |
| --- | --- | --- |
| `mode` | `token` | `token`, `mtls`, or `none`. |
| `enable_insecure` | `false` | Must be `true` to allow `mode = none`. |
| `token_file` | `/etc/opaquedb/tokens` | |
| `ca_cert` | `""` | Client CA for `mtls`. |

### `[blobstore]`

| Key | Default | Notes |
| --- | --- | --- |
| `kind` | `local` | `local` or `s3`. |
| `path` | `/var/lib/opaquedb/keys` | |

### `[metrics]`

| Key | Default |
| --- | --- |
| `listen` | `0.0.0.0:9090` |

### `[logging]`

| Key | Default | Notes |
| --- | --- | --- |
| `level` | `info` | |
| `format` | `json` | `json` or `text`. |
| `file` | `""` | Empty means standard output. |

Logging is configured once by `log::Init`, which reads `config.logging`. CLI data
output still goes to stdout because it is data, not a log line.
