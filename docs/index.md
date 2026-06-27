# OpaqueDB

OpaqueDB answers SQL queries over data without learning what you asked for. A
client encrypts the value it is searching for under its own key. The server
evaluates the match over encrypted data and returns an encrypted result that
only the client can decrypt. The operator runs the query but never sees the
query value or the secret key.

It is a computational private information retrieval (PIR) system built on
[Microsoft SEAL](https://github.com/microsoft/SEAL) with the BFV scheme. The
deployed unit is a sharded cluster of identical nodes. Sharding spreads the
linear scan that PIR requires across many machines.

## The privacy guarantee

- Privacy rests on Ring-LWE, a lattice assumption with no known quantum attack.
- It holds against a semi-honest operator. There is no non-collusion assumption
  between servers, so the whole cluster is one trust domain.
- Today the system is QueryPrivate: the operator never learns the query value.
  DataPrivate mode, where the operator also never learns the stored data, is a
  later release.

## What it is not

- **Not a full SQL engine yet.** The engine evaluates one searchable column, the
  primary `KEY` or any secondary `INDEX`, with `=`, `<>` (`!=`), `IN (...)`, or a
  same-column `OR`, optionally with `LIMIT`/`OFFSET` or `COUNT(*)`. A `SELECT`
  with no `WHERE` is a plaintext full scan. Cross-column conditions, `LIKE`, and
  ranges (`<`, `>`, `BETWEEN`) parse but are not evaluated under encryption yet.
  See the [SQL reference](sql.md) for the exact boundary.
- **Not a way to skip work.** PIR requires a full linear scan. Sharding improves
  latency and throughput, not total work.
- **Not anonymity.** Authentication is access control. OpaqueDB hides the query
  value, never who is asking. Client anonymity is a layer you add above the
  database, not a property it gives you.
- **No client SDK.** The gRPC `.proto` files are the wire contract. The `query`
  subcommand is a dev test client.

## Where to go next

- [Quickstart](quickstart.md): load a table and run a private query.
- [SQL reference](sql.md): the full query syntax, with examples.
- [Use cases](use-cases.md): what to build on private lookups, with schemas.
- [How it works](how-it-works.md): the bit-sliced matching algorithm and the
  FHE parameters.
- [Architecture](architecture.md): layering, components, and the libraries used.
- [Building and development](building.md): the toolchain and the `Makefile`.
- [Configuration](configuration.md): every setting and how it resolves.
- [CLI reference](cli.md): the commands.
- [Cluster](cluster.md): multi-node sharding with etcd.
- [Security](security.md): the trust model and hard constraints.

## License

Apache-2.0.
