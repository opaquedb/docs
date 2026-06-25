# Building and development

The build uses CMake with Ninja and vcpkg in manifest mode. Dependencies are
pinned by the `builtin-baseline` in `vcpkg.json` and built from source on the
first configure.

## The dev container

The `.devcontainer/` in the main repo provides the full C++20 toolchain, cmake,
ninja, vcpkg (`$VCPKG_ROOT=/opt/vcpkg`), and the lint tools. Opening the repo in
a dev container is the supported way to get a working environment.

## The Makefile

The `Makefile` is the single source of truth for build, test, lint, and
packaging. CI, the release workflow, and these docs all invoke the same targets.
Run `make help` to list them.

```sh
export VCPKG_ROOT=/opt/vcpkg   # provided by the dev container
make configure                 # cmake --preset dev; first run builds deps
make build                     # cmake --build --preset dev
make test                      # ctest --preset dev
make lint                      # clang-format check + clang-tidy
make package                   # release build, then CPack .deb + .tar.gz
```

| Target | Does |
| --- | --- |
| `configure` | Configure the build. `PRESET=dev` (Debug, `-Werror`) or `PRESET=release`. |
| `build` | Build the configured preset. |
| `test` | Run the test suite. |
| `format` | Reformat all C++ sources in place. |
| `format-check` | Check formatting without modifying files. |
| `tidy` | Run clang-tidy against the dev build. |
| `lint` | `format-check` then `tidy`. CI enforces both. |
| `package` | CPack `.deb` and `.tar.gz` from an existing release build. |
| `release` | Full release build, then package. |
| `clean` | Remove the build trees. |
| `all` | Configure, build, and test. |

Override the preset with `PRESET=release`, for example
`make build PRESET=release`. The raw `cmake --preset dev`, `cmake --build`, and
`ctest` commands still work; the Makefile just wraps them.

## Presets and performance

The `dev` preset is Debug (`-O0`) with `-Werror`. SEAL arithmetic is about 30x
slower in Debug. At poly 16384 a small query is tens of seconds in Debug versus
well under a second warm in Release. **Always measure real workloads with
`make build PRESET=release`**; the binary is `build/release/opaquedb`.

The first configure is slow because vcpkg builds dependencies from source. Later
builds use the binary cache.

## Examples

The `examples/` tree builds with the rest of the source and is the supported way
to drive the client crypto and the wire contract until a separate client SDK
exists.

| Example | What it does |
| --- | --- |
| `direct_engine` | In-process, no network. Declares the weather table, loads rows, encrypts a key, runs a private SELECT, decodes the result. The shortest path through SQL, crypto, storage, and PIR together. |
| `e2e_client` | A standalone gRPC client. Generates a keypair, registers public keys, encrypts the WHERE value, calls Execute, decrypts the result. Run against a node with data loaded. |
| `crypto_bench` | Times the SEAL primitives the scan relies on at the default FHE parameters. Build in release; Debug timings are meaningless. |

## Versioning and release

Git-flow (AVH) drives branches: `main` is production, `develop` is integration,
and work merges through `release/*` and `hotfix/*`. Tags are `vX.Y.Z`.

The version lives only in the CMake `project(VERSION)` (checked against
`vcpkg.json` at configure time) and flows to `OPAQUEDB_VERSION`, `--version`, and
CPack. Finishing a release (`git flow release finish X.Y.Z`) tags `vX.Y.Z` on
`main`; pushing that tag triggers the release workflow, which builds the release
preset, runs CPack, and publishes a GitHub Release with the `.deb` and `.tar.gz`
attached. CI runs the format gate then build, test, and tidy on pushes and PRs,
all through `make`.

## Contributing

- The build must be warning-clean. The `dev` preset sets `OPAQUEDB_WERROR=ON`.
- Google C++ style, enforced by `.clang-format`. CI runs it in check mode.
- `.clang-tidy` runs in CI; keep it clean.
- Errors use `absl::Status` and `absl::StatusOr` at fallible boundaries.
- Plain, direct English in comments and messages. Comments explain why.
- Never log secret key material, plaintext query values, or auth tokens.
- The `.proto` files are the single source of truth for the wire format; the
  epoch manifest is the single source of truth for the schema. Both carry a
  version field. Bump it when the format changes.
