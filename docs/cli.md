# CLI reference

The `opaquedb` binary is one CLI built with CLI11. Command sources live under
`src/cli/commands/`. Every command accepts the global config layers described in
[Configuration](configuration.md), including `--set section.key=value`.

Most commands take `--database D` (default `default`) and resolve the table from
the SQL or a `--table` flag.

## `run`

Start a node.

```sh
opaquedb run
opaquedb run --set auth.mode=none --set auth.enable_insecure=true   # local dev
```

## `load`

Ingest a schema and a CSV. The CSV header names the columns. This is the only
command that takes `--schema`; it is the DDL that defines the table.

```sh
opaquedb load --schema examples/weather.sql --csv examples/weather.csv
opaquedb load --schema weather.sql --csv weather.csv --database analytics
```

For a sharded cluster, load only this node's shard:

```sh
opaquedb load --schema weather.sql --csv weather.csv \
  --shard-id 0 --shard-nodes node1,node2,node3
```

## `query`

Run one `SELECT` and print the decoded rows. A `WHERE` query matches privately; a
query with no `WHERE` is a plaintext scan.

```sh
opaquedb query 'SELECT country, temperature FROM weather WHERE city = "Tokyo"'
```

The client fetches the table schema from the node (the `DescribeTable` RPC) and
decodes rows from it, so `query` does not take `--schema`. The full query syntax,
including `<>`, `IN`, `COUNT(*)`, `LIMIT`/`OFFSET`, `ORDER BY`, and `DISTINCT`, is
in the [SQL reference](sql.md).

| Flag | Default | Notes |
| --- | --- | --- |
| `--param name=value` | | Bind a `:name` parameter. Repeatable. |
| `--database D` | `default` | The database to query. |
| `--target host:port` | from config | The node to dial. |
| `--client-id ID` | `dev` | Client id used to register keys. |
| `--backend NAME` | | Backend hint. |
| `--token T` | | Bearer token for token auth mode. |

```sh
opaquedb query 'SELECT country FROM weather WHERE city = :c' --param c=Amsterdam
```

## `repl`

Interactive shell with line editing and tab completion. Registers keys once, then
runs each statement. Statements end with a semicolon and may span lines. Up and
down recall history (saved to `$OPAQUEDB_HISTORY` or `~/.opaquedb_history`), and
tab completes keywords plus known table and column names.

```console
$ opaquedb repl
OpaqueDB shell. \help for commands, \quit to exit.
opaquedb(default)> SELECT country FROM weather WHERE city = "Amsterdam";
 country
---------
 NL
```

Meta-commands:

| Command | Does |
| --- | --- |
| `\use <database>` | Switch the current database. |
| `\tables` | List tables in the current database. |
| `\d <table>` | Show a table's columns. |
| `\timing` | Toggle query timing on or off. |
| `\help` (`\h`) | Show the command list. |
| `\quit` (`\q`) | Exit. |

Flags: `--target`, `--client-id` (default `repl`), `--token`, `--database`.

## `insert`

Append one row over the `Insert` RPC. Epochs are immutable, so this copies the
existing rows, appends the encoded new row, and publishes a new version reusing
the schema, key_bits, and geometry.

Values are given in schema order (`id city country temperature humidity
conditions`):

```sh
opaquedb insert --table weather --database default \
  10 Rome IT 24 55 Clear
```

Plaintext today and single-node oriented; it does not advance a global cluster
epoch (tracked TODO).

## `token`

Provision auth tokens for token mode.

```sh
opaquedb token mint --id analyst --role query
opaquedb token mint --id ops --role admin --bytes 32
```

`mint` prints one `id role token` line of a `/dev/urandom` token. Roles are
`query` or `admin`.

## `config`

```sh
opaquedb config init          # write the default config file verbatim
```

## Admin commands

Per-table admin runs in-process. The remote admin gRPC is still single-table.

```sh
opaquedb status --database default --table weather
opaquedb tables                                   # list db.table via the catalog
opaquedb schema inspect --database default --table weather
opaquedb epoch list --database default --table weather
opaquedb epoch rollback --database default --table weather
```

## Other

```sh
opaquedb --version
opaquedb --help
```
