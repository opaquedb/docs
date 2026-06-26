# Quickstart

This walks through declaring a table, loading a CSV, serving it, and running a
private query. It assumes you have built the `opaquedb` binary. See
[Building and development](building.md) if you have not.

## 1. Declare a schema

A schema is one `CREATE TABLE`. Exactly one column is the primary `KEY` (it is
searchable and shards the data). Any column may also be marked `INDEX` to make it
searchable too. A `KEY` or `INDEX` column must be `INT` or `TEXT`, not `REAL`.
The remaining columns are typed payload (`INT`, `REAL`, `TEXT`) that is returned
but not matched.

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
column is the one exception, matched but not returned.

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

## 3. Run private queries

Open the interactive shell and query by any searchable column, the primary `KEY`
or any `INDEX`:

```console
$ opaquedb repl --schema examples/weather.sql
OpaqueDB shell. \help for commands, \quit to exit.
opaquedb(default)> SELECT city, temperature, conditions FROM weather WHERE id = 1
city=Amsterdam temperature=18 conditions=Cloudy
opaquedb(default)> SELECT city, temperature FROM weather WHERE country = "JP"
city=Tokyo temperature=27
opaquedb(default)> SELECT country FROM weather WHERE city = "Atlantis"
(no rows)
opaquedb(default)> \quit
```

A one-shot query works the same way:

```console
$ opaquedb query 'SELECT country, temperature, conditions FROM weather WHERE city = "Amsterdam"' \
    --schema examples/weather.sql
country=NL temperature=18 conditions=Cloudy
```

`"Amsterdam"` is encrypted before it leaves the client. The node scans every row
under encryption and returns only the encrypted match. A no-match query returns
an encrypted empty result, so the operator never learns whether a query matched.
The value is encrypted whichever column you match on, so a query on a secondary
`INDEX` reveals no more to the operator and takes the same encrypted round trip
as a query on the key.

A searchable value can match several rows. `LIMIT` and `OFFSET` page through them;
the default is `LIMIT 1`. Two cities share `conditions = "Sunny"`, and `LIMIT`
returns both in one query:

```console
$ opaquedb query 'SELECT city, country, temperature FROM weather WHERE conditions = "Sunny" LIMIT 5' \
    --schema examples/weather.sql
city=Nairobi country=KE temperature=24
city=Cairo country=EG temperature=33
```

`LIMIT` and `OFFSET` are public and applied client-side over the decoded matches.
See [How it works](how-it-works.md#multiple-results-limit-and-offset) for the
buckets that carry them.

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
