# SQL reference

OpaqueDB speaks a small SQL subset: one `CREATE TABLE` per schema and a `SELECT`
that the server can either match under encryption or read as a plaintext scan.
This page is the full grammar, what runs privately versus on the client, and a
worked example for every supported form.

The examples use the weather table that ships in `examples/`:

```sql
CREATE TABLE weather (
  id INT KEY,
  city TEXT INDEX,
  country TEXT INDEX,
  temperature INT,
  humidity INT,
  conditions TEXT INDEX
);
```

| id | city | country | temperature | humidity | conditions |
| --- | --- | --- | --- | --- | --- |
| 1 | Amsterdam | NL | 18 | 72 | Cloudy |
| 2 | Tokyo | JP | 27 | 61 | Clear |
| 3 | Nairobi | KE | 24 | 55 | Sunny |
| 4 | Reykjavik | IS | 9 | 80 | Rain |
| 5 | Santiago | CL | 21 | 40 | Clear |
| 6 | Toronto | CA | 15 | 67 | Overcast |
| 7 | Cairo | EG | 33 | 30 | Sunny |
| 8 | Wellington | NZ | 13 | 75 | Windy |
| 9 | London | GB | 11 | 77 | Drizzle |

## At a glance

| Feature | Status | Where it runs |
| --- | --- | --- |
| `CREATE TABLE` with `KEY` / `INDEX` | Supported | Schema (DDL) |
| `WHERE col = :v` | Private match | Server, under encryption |
| `WHERE col <> :v` (`!=`) | Private match | Server, same cost as `=` |
| `WHERE col IN (...)` | Private match | Server, one operand per value |
| `WHERE col = a OR col = b` (same column) | Private match | Server, union of operands |
| `SELECT COUNT(*) ... WHERE` | Private count | Server, exact |
| `SELECT` with no `WHERE` | Plaintext scan | Server, single node |
| `ORDER BY`, `DISTINCT`, `AS` | Supported | Client, over returned rows |
| `LIMIT` / `OFFSET` | Supported | Client, over returned rows |
| `col < v`, `>`, `<=`, `>=`, `BETWEEN` | Parses, not evaluated | Rejected by the planner |
| `LIKE` | Parses, not evaluated | Rejected by the planner |
| `col1 = a AND col2 = b` (cross column) | Parses, not evaluated | Rejected by the planner |
| `OR` across two columns | Parses, not evaluated | Rejected by the planner |

"Parses, not evaluated" means the grammar accepts it so the AST node already
exists, but the plan builder returns an error today. Widening what the engine
evaluates under encryption is active work, so this list grows over time.

## CREATE TABLE

A schema is exactly one `CREATE TABLE`. It defines the columns, their types, and
which ones are searchable.

```sql
CREATE TABLE name (
  col TYPE [KEY | INDEX],
  ...
);
```

### Column types

| Type | Stored as | Notes |
| --- | --- | --- |
| `INT` | 8 bytes | Signed integer. |
| `REAL` | 8 bytes | Floating point. Payload only, never searchable. |
| `TEXT` | 2-byte length + bytes | UTF-8 string. |
| `JSON` | 2-byte length + bytes | Same layout as `TEXT`, but validated as well-formed JSON on insert, so clients get back parseable JSON. Payload only. |

### Column roles

Every column has one role. The role decides whether the column can be searched
and whether it comes back in a result.

- **`KEY`** is the one primary key. Exactly one column must have it. It is
  matched and it shards the data, but it is **not** stored in payload, so it is
  matched but never returned. It must be `INT` or `TEXT`.
- **`INDEX`** marks a secondary searchable column. A table may have any number.
  It is matched like the key **and** stored in payload, so it is also returned.
  It must be `INT` or `TEXT`.
- **No marker** is a payload column: returned, never matched. Any type.

A query matches on whichever single column its `WHERE` names, so the weather
table can be looked up by `id`, `city`, `country`, or `conditions`. Matching a
secondary `INDEX` costs the operator no more information than matching the key
and takes the same encrypted round trip.

!!! note "TEXT keys are candidate matches"
    A `TEXT` searchable value is hashed into the `2^key_bits` universe (default
    `key_bits = 16`), so two different strings can collide. For high-cardinality
    keys such as hashes or ids, raise `crypto.key_bits` and verify the returned
    row on the client. See [How it works](how-it-works.md#fhe-parameters).

No SQL comments are allowed inside a schema. Use `--` lines only outside the
statement.

## SELECT

```text
SELECT [DISTINCT] projection
FROM table
[WHERE predicate]
[ORDER BY col [ASC | DESC], ...]
[LIMIT n] [OFFSET m]

projection := * | COUNT(*) | col [AS name] (, col [AS name])*
predicate  := col = value
            | col <> value          (also !=)
            | col IN (value, ...)
            | col = a OR col = b     (same column, flat)
```

`value` is either an inline literal (`"Tokyo"`, `27`) or a bound parameter
(`:name`). A literal is the secret you are searching for, so the client lifts it
out, encrypts it, and rewrites the query to a parameter before it leaves the
machine. The server only ever sees the parameterized template. See
[Literals and parameters](#literals-and-parameters).

`LIMIT` defaults to 10. A bare query returns up to ten rows.

### Equality: the private lookup

The core operation. The server scans every row under encryption and returns only
the encrypted match.

```console
$ opaquedb query 'SELECT city, temperature, conditions FROM weather WHERE id = 1'
 city      | temperature | conditions
-----------+-------------+------------
 Amsterdam | 18          | Cloudy
```

Match on any searchable column, key or index:

```console
$ opaquedb query 'SELECT city, temperature FROM weather WHERE country = "JP"'
 city  | temperature
-------+-------------
 Tokyo | 27
```

A no-match returns an encrypted empty result, so the operator never learns
whether the query hit anything:

```console
$ opaquedb query 'SELECT country FROM weather WHERE city = "Atlantis"'
(no rows)
```

### Inequality: `<>` and `!=`

`WHERE col <> :v` matches every row whose value differs. It hides the value the
same way `=` does and costs the operator exactly the same (the matcher flips the
equality indicator, adding no encrypted multiplies).

```console
$ opaquedb query 'SELECT city, conditions FROM weather WHERE conditions <> "Sunny" LIMIT 3'
 city      | conditions
-----------+------------
 Amsterdam | Cloudy
 Tokyo     | Clear
 Reykjavik | Rain
```

A `<>` usually matches many rows. Returning them all follows the same bucket
rules as any multi-row result, so some can collide and drop from the returned
set. A `COUNT(*)` over `<>` stays exact regardless (see below).

### A set of values: `IN` and same-column `OR`

`WHERE col IN (...)` matches several values on one column in a single query. Each
value is encrypted separately, so the operator learns nothing about any of them.

```console
$ opaquedb query 'SELECT city, country, temperature FROM weather WHERE city IN ("Tokyo", "Cairo", "London")'
 city   | country | temperature
--------+---------+-------------
 London | GB      | 11
 Tokyo  | JP      | 27
 Cairo  | EG      | 33
```

A flat `OR` on the same column is the same union written differently:

```console
$ opaquedb query 'SELECT city, temperature FROM weather WHERE city = "Tokyo" OR city = "Nairobi"'
 city    | temperature
---------+-------------
 Nairobi | 24
 Tokyo   | 27
```

`IN` works on the key too, for example `WHERE id IN (1, 5, 9)`. Duplicate values
in the list are de-duplicated by the client before encryption. There is no added
multiplicative depth: each extra value is one more equality indicator, summed
into the union.

### Count matches privately

`SELECT COUNT(*)` returns the number of matching rows as a single number and
nothing else. The count is exact, even when rows would collide in a result
bucket, and the operator still never sees the value.

```console
$ opaquedb query 'SELECT COUNT(*) FROM weather WHERE conditions = "Sunny"'
2
```

It works with `<>` and `IN` too:

```console
$ opaquedb query 'SELECT COUNT(*) FROM weather WHERE conditions <> "Sunny"'
7
```

### Multiple matches: LIMIT and OFFSET

A searchable value can match many rows. `LIMIT n` caps how many come back and
`OFFSET m` pages through them. Rows come back in a stable order across queries,
so paging is deterministic.

```console
$ opaquedb query 'SELECT city, country FROM weather WHERE conditions = "Sunny"'
 city    | country
---------+---------
 Nairobi | KE
 Cairo   | EG

$ opaquedb query 'SELECT city, country FROM weather WHERE conditions = "Sunny" LIMIT 1 OFFSET 1'
 city  | country
-------+---------
 Cairo | EG
```

`LIMIT` and `OFFSET` are public. They are not secret, so they stay in the
plaintext template and the client applies them over the decoded rows. A single
value returns at most `crypto.result_buckets` rows (default 16) in one round
trip; raise that setting to return more per query. `LIMIT` counts rows, not
bucket slots, and the encrypted result does not grow with the limit. See
[How it works](how-it-works.md#multiple-results-limit-and-offset).

## Plaintext scan: SELECT with no WHERE

A `SELECT` with no `WHERE` has no value to hide, so it reads the table directly
and returns rows in the clear. This is a plaintext scan, not the encrypted
matcher. Do not read it as a private query.

```console
$ opaquedb query 'SELECT city, temperature FROM weather ORDER BY temperature DESC LIMIT 3'
 city  | temperature
-------+-------------
 Cairo | 33
 Tokyo | 27
 Nairobi | 24
```

A scan still defaults to `LIMIT 10` and runs on a single node. A full scan
against a sharded cluster is rejected rather than returning a partial answer.

## Client-side clauses

`ORDER BY`, `DISTINCT`, and column aliases (`AS`) are public presentation
controls. The client applies them over the rows it gets back, not the server.

```console
$ opaquedb query 'SELECT DISTINCT country FROM weather ORDER BY country LIMIT 4'
 country
---------
 CA
 CL
 EG
 GB

$ opaquedb query 'SELECT city AS town, temperature AS temp_c FROM weather WHERE id = 2'
 town  | temp_c
-------+--------
 Tokyo | 27
```

Because they run on the client, they sort and de-duplicate only the rows that
came back. For a matched query that is at most `crypto.result_buckets` rows; for
a scan it is what the server returned (a scan caps how many rows it reads). A
bare `ORDER BY ... LIMIT 5` over a table larger than that window is **not** a
global top-5.

`ORDER BY` can only name a returned column. The primary key is not returned, so
you cannot order on it.

## Literals and parameters

A `WHERE` value is either an inline literal or a bound parameter.

- **Inline literal** (`= "London"`, `= 27`). This is the secret value, so it is
  client-side sugar. The client lifts it out, encrypts it, and rewrites the
  query to `:v` before sending. For `IN` and same-column `OR`, every literal is
  lifted and rewritten to `:v0, :v1, ...`.
- **Bound parameter** (`:name`). Supply the value with `--param name=value`. The
  client encrypts it the same way.

```console
$ opaquedb query 'SELECT country, temperature FROM weather WHERE city = :c' --param c=Amsterdam
 country | temperature
---------+-------------
 NL      | 18
```

The server rejects any query that still carries a literal, so the operator only
ever sees the parameterized template. A literal value never crosses the wire.

## Not evaluated yet

These parse into the AST but the plan builder rejects them today. They are listed
so you know the boundary, not because you can use them.

| Form | Error you get |
| --- | --- |
| `col < v`, `>`, `<=`, `>=` | "parsed but not yet evaluated; only '=' and '<>' are supported" |
| `col BETWEEN a AND b` | "BETWEEN is parsed but not yet evaluated" |
| `col LIKE :p` | "LIKE is parsed but not yet evaluated" |
| `col1 = a AND col2 = b` | "multiple predicates joined by AND are parsed but not yet evaluated" |
| `OR` spanning two columns | "is not yet evaluated; use OR on a single column" |

Ranges and `LIKE` need an order-preserving or prefix encoding that the current
bit-sliced equality matcher does not provide. Cross-column conjunctions need
combining indicators across columns. Both are tracked work.

## Next

- [Quickstart](quickstart.md): load a table and run these queries end to end.
- [How it works](how-it-works.md): the matching algorithm behind each form.
- [CLI reference](cli.md): every command and flag.
- [Use cases](use-cases.md): schemas built on private lookups.
