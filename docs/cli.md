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

Ingest a schema and a CSV. The CSV header names the columns.

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

Run one private SELECT and print the decoded row.

```sh
opaquedb query 'SELECT country, temperature FROM weather WHERE city = "Tokyo"' \
  --schema examples/weather.sql
```

The WHERE clause takes an inline literal (the secret value, encrypted
client-side) or a bound parameter `:name`.

## `repl`

Interactive shell with line editing and tab completion. Registers keys once,
then runs each SELECT privately.

```console
$ opaquedb repl --schema examples/weather.sql
opaquedb(default)> SELECT country FROM weather WHERE city = "Amsterdam"
```

Meta-commands: `\use <db>`, `\schema <file>`, `\tables`, `\help`, `\quit`.

## `insert`

Append one row over the `Insert` RPC. Epochs are immutable, so this copies the
existing rows, appends the encoded new row, and publishes a new version reusing
the schema, key_bits, and geometry.

```sh
opaquedb insert --table weather --database default \
  Rome 9 IT 24 55 Clear
```

Plaintext today and single-node oriented; it does not advance a global cluster
epoch (tracked TODO).

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
