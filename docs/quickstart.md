# Quickstart

This walks through declaring a table, loading a CSV, serving it, and running a
private query. It assumes you have built the `opaquedb` binary. See
[Building and development](building.md) if you have not.

## 1. Declare a schema

A schema is one `CREATE TABLE`. Exactly one column is the primary `KEY` (it is
searchable and shards the data). Any column may also be marked `INDEX` to make it
searchable too. A `KEY` or `INDEX` column must be `INT` or `TEXT`. The remaining
columns are typed payload (`INT`, `REAL`, `TEXT`, `JSON`) that is returned but
not matched.

```sql
-- weather.sql
CREATE TABLE weather (
  id INT KEY,
  city TEXT INDEX,
  country TEXT INDEX,
  temperature INT,
  humidity INT,
  conditions TEXT INDEX
);
```

A query matches on whichever column its `WHERE` names, so this table can be
looked up by `id`, `city`, `country`, or `conditions`. An `INDEX` column is
stored both as a search key and as payload, so it is also returned; the `KEY`
column is the one exception, matched but not returned. For the full column rules
and query syntax, see the [SQL reference](sql.md).

The CSV header names the columns:

```text
id,city,country,temperature,humidity,conditions
1,Amsterdam,NL,18,72,Cloudy
2,Tokyo,JP,27,61,Clear
3,Nairobi,KE,24,55,Sunny
4,Reykjavik,IS,9,80,Rain
5,Santiago,CL,21,40,Clear
6,Toronto,CA,15,67,Overcast
7,Cairo,EG,33,30,Sunny
8,Wellington,NZ,13,75,Windy
9,London,GB,11,77,Drizzle
```

These example files ship in `examples/weather.sql` and `examples/weather.csv`.

## 2. Start a node and load the data

This runs a single node in local insecure dev mode (no auth).

```sh
opaquedb run --set auth.mode=none --set auth.enable_insecure=true &
opaquedb load --schema examples/weather.sql --csv examples/weather.csv
```

Only `load` takes `--schema`; it is the DDL that defines the table. The `query`
and `repl` commands fetch the schema from the node, so they do not need it.

## 3. Run private queries

Open the interactive shell and query by any searchable column, the primary `KEY`
or any `INDEX`. Statements end with a semicolon and may span lines.

```console
$ opaquedb repl
OpaqueDB shell. \help for commands, \quit to exit.
opaquedb(default)> SELECT city, temperature, conditions FROM weather WHERE id = 1;
 city      | temperature | conditions
-----------+-------------+------------
 Amsterdam | 18          | Cloudy
opaquedb(default)> SELECT city FROM weather WHERE country = "JP";
 city
-------
 Tokyo
opaquedb(default)> SELECT country FROM weather WHERE city = "Atlantis";
(no rows)
opaquedb(default)> \quit
```

A one-shot query works the same way:

```console
$ opaquedb query 'SELECT country, temperature, conditions FROM weather WHERE city = "Amsterdam"'
 country | temperature | conditions
---------+-------------+------------
 NL      | 18          | Cloudy
```

`"Amsterdam"` is encrypted before it leaves the client. The node scans every row
under encryption and returns only the encrypted match. A no-match query returns
an encrypted empty result, so the operator never learns whether a query matched.
The value is encrypted whichever column you match on, so a query on a secondary
`INDEX` reveals no more to the operator and takes the same encrypted round trip
as a query on the key.

## 4. More than one match

A searchable value can match several rows. The default is `LIMIT 10`, so a bare
query returns up to ten matches. Two cities share `conditions = "Sunny"`, and
both come back:

```console
$ opaquedb query 'SELECT city, country FROM weather WHERE conditions = "Sunny"'
 city    | country
---------+---------
 Nairobi | KE
 Cairo   | EG
```

`LIMIT n` caps the rows and `OFFSET m` pages through them in a stable order:

```console
$ opaquedb query 'SELECT city, country FROM weather WHERE conditions = "Sunny" LIMIT 1 OFFSET 1'
 city  | country
-------+---------
 Cairo | EG
```

## 5. Beyond equality

The engine also matches a set of values, excludes a value, and counts privately.
Each value is encrypted, so the operator learns nothing about any of them.

```console
$ opaquedb query 'SELECT city, temperature FROM weather WHERE city IN ("Tokyo", "Cairo")'
 city  | temperature
-------+-------------
 Tokyo | 27
 Cairo | 33

$ opaquedb query 'SELECT COUNT(*) FROM weather WHERE conditions <> "Sunny"'
7
```

A `SELECT` with no `WHERE` is a plaintext scan (there is no value to hide), with
client-side `ORDER BY`, `DISTINCT`, and aliases:

```console
$ opaquedb query 'SELECT DISTINCT country FROM weather ORDER BY country LIMIT 3'
 country
---------
 CA
 CL
 EG
```

See the [SQL reference](sql.md) for every supported form and the exact boundary
of what runs under encryption.

## How a literal is handled

A `WHERE` clause takes either a bound parameter (`:name`) or an inline literal
(`= "London"`). An inline literal is the secret value, so it is client-side
sugar: the client lifts it out, encrypts it, and rewrites the query to `:v`. The
server rejects any literal, so the operator only ever sees the parameterized
template.

## Next

- [SQL reference](sql.md) for the full query syntax.
- [How it works](how-it-works.md) for the matching algorithm.
- [CLI reference](cli.md) for every command and flag.
- [Cluster](cluster.md) to run a sharded multi-node setup.
