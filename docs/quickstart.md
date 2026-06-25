# Quickstart

This walks through declaring a table, loading a CSV, serving it, and running a
private query. It assumes you have built the `opaquedb` binary. See
[Building and development](building.md) if you have not.

## 1. Declare a schema

A schema is one `CREATE TABLE`. Exactly one column is the match `KEY`; the rest
are typed payload columns (`INT`, `REAL`, `TEXT`).

```sql
-- weather.sql
CREATE TABLE weather (
  city TEXT KEY,
  id INT,
  country TEXT,
  temperature INT,
  humidity INT,
  conditions TEXT
);
```

The CSV header names the columns:

```text
id,city,country,temperature,humidity,conditions
1,Amsterdam,NL,18,72,Cloudy
2,Tokyo,JP,27,61,Clear
```

These example files ship in `examples/weather.sql` and `examples/weather.csv`.

## 2. Start a node and load the data

This runs a single node in local insecure dev mode (no auth).

```sh
opaquedb run --set auth.mode=none --set auth.enable_insecure=true &
opaquedb load --schema examples/weather.sql --csv examples/weather.csv
```

## 3. Run private queries

Open the interactive shell and query by the key:

```console
$ opaquedb repl --schema examples/weather.sql
OpaqueDB shell. \help for commands, \quit to exit.
opaquedb(default)> SELECT country, temperature, conditions FROM weather WHERE city = "Amsterdam"
country=NL temperature=18 conditions=Cloudy
opaquedb(default)> SELECT country FROM weather WHERE city = "Atlantis"
(no rows)
opaquedb(default)> \quit
```

A one-shot query works the same way:

```console
$ opaquedb query 'SELECT country, temperature FROM weather WHERE city = "Tokyo"' \
    --schema examples/weather.sql
country=JP temperature=27
```

`"Tokyo"` is encrypted before it leaves the client. The node scans every row
under encryption and returns only the encrypted match. A no-match query returns
an encrypted empty result, so the operator never learns whether a query matched.

## How a literal is handled

A WHERE clause takes either a bound parameter (`:name`) or an inline literal
(`= "London"`). An inline literal is the secret value, so it is client-side
sugar: the client lifts it out, encrypts it, and rewrites the query to `:v`. The
server rejects any literal, so the operator only ever sees the parameterized
template.

## Next

- [How it works](how-it-works.md) for the matching algorithm.
- [CLI reference](cli.md) for every command and flag.
- [Cluster](cluster.md) to run a sharded multi-node setup.
