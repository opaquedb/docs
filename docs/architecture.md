# Architecture

OpaqueDB is a set of C++20 libraries with a strict, one-directional dependency
graph. Each `src/<dir>` is its own CMake library target, and dependencies may
only point downward. CMake target visibility enforces the direction, so a
forbidden include fails to link.

## Layering

```text
config, core            foundational; everything may depend on them
config        <-  log     (spdlog; the one logging entry point)
core  <-  crypto  <-  backend (interface + concrete backends)
core  <-  storage
core  <-  sql  <-  planner
config, core, storage, crypto  <-  admin
all of the above  <-  auth, cluster, server, client, cli
```

Rules that hold:

- **crypto** is the only SEAL boundary. It reads FHE parameters from config and
  knows nothing about SQL.
- **storage** stores opaque bytes. It knows nothing about crypto and does not
  link SEAL. Slot geometry reaches it as plain integers, never SEAL types.
- **backends** live under `src/backend/<name>/` (for example
  `backend/reference`). Each is its own target that links the `backend`
  interface, depends on crypto and on the columns handed to it, and not on SQL
  or transport.
- **main.cpp** only wires things together. It holds no logic.

## Components

| Layer | Responsibility |
| --- | --- |
| `config` | The one place settings live. Resolved once into an immutable `Config` and injected. |
| `core` | Foundational types and codecs: key codec, slot codec, record codec, schema. |
| `log` | Logging configured once by `log::Init` over spdlog. |
| `crypto` | The SEAL boundary: encrypt, decrypt, key handling, parameter validation. |
| `backend` | The matcher interface; concrete backends evaluate the encrypted scan. |
| `storage` | Immutable epoch segments, WAL, manifests, catalog. Opaque bytes only. |
| `sql` / `planner` | Parse `CREATE TABLE` and queries; build the logical plan. |
| `admin` | Transport-agnostic `AdminService` (publish, list, rollback, status, schema, principals) and `KeyringStore`. |
| `auth` | `Authenticator` (token / mtls / none), gRPC-free; `RequestGate` runs auth then rate-limit. |
| `cluster` | etcd membership, lease and keepalive, leader election, shard-map publish. |
| `server` | gRPC services, the query engine, the repository manager, publish path. |
| `client` | The one wire query client, `client::QueryClient`. |
| `cli` | CLI11 commands under `src/cli/commands/`. |

## Single sources of truth

The project is strict about not duplicating definitions:

- The `.proto` files define the wire types. Nothing hand-duplicates them.
- Common build, test, lint, and packaging commands live once in the `Makefile`.
- The `Config` struct is the only place settings live.
- The bit-sliced key codec (`core::key_codec`) and the SIMD plane layout
  (`core::slot_codec`) live once in `core`.
- The default config is one file, `config/opaquedb.default.toml`, embedded at
  build time.
- The version is the CMake `project(VERSION)` only.
- The schema lives once in the epoch manifest; the FHE parameter set lives once
  in config.
- Management logic lives once in `AdminService`; the gRPC adapter and the CLI
  are thin clients over it.
- Logging is configured once by `log::Init`.

## Libraries

All dependencies flow through [vcpkg](https://vcpkg.io/) in manifest mode,
pinned by the baseline in `vcpkg.json`.

| Library | Used for |
| --- | --- |
| [Microsoft SEAL](https://github.com/microsoft/SEAL) | BFV homomorphic encryption, the crypto boundary. |
| [gRPC](https://grpc.io/) + [Protobuf](https://protobuf.dev/) | Client and node-to-node RPC, the wire contract. |
| [Abseil](https://abseil.io/) | `absl::Status` / `absl::StatusOr` and core utilities. |
| [etcd-cpp-apiv3](https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3) | Cluster membership, leader election, shard map. Vendored as an overlay port, core-only. |
| [CLI11](https://github.com/CLIUtils/CLI11) | Command-line parsing. |
| [replxx](https://github.com/AmokHuginnsson/replxx) | Line editing and tab completion in the `repl` shell. |
| [spdlog](https://github.com/gabime/spdlog) | The single logging entry point. |
| [tomlplusplus](https://github.com/marzer/tomlplusplus) | Config file parsing. |
| [nlohmann-json](https://github.com/nlohmann/json) | Epoch manifests and JSON logs. |
| [GoogleTest](https://github.com/google/googletest) | The test suite. |

## Error handling

Fallible API boundaries return `absl::Status` or `absl::StatusOr`. Exceptions
are reserved for programmer errors. SEAL throws on bad input, so the crypto
boundary catches and converts to a status. There are no silent failures and no
ad hoc error codes.
