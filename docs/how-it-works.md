# How it works

OpaqueDB matches a query against stored rows without decrypting either. This
page explains the matching algorithm, the data model it runs over, and the FHE
parameters that make it fit.

## The data model

A schema is one `CREATE TABLE name (col TYPE [KEY|INDEX], ...)`. Types are `INT`,
`REAL`, and `TEXT`. Exactly one column is the primary `KEY`, and any number of
columns may be marked `INDEX`. A `KEY` or `INDEX` column must be `INT` or `TEXT`,
not `REAL`.

Each column has one of three roles:

- **Primary key** (`KEY`). The one matched column that also shards the data. It
  is not stored in payload, so it is matched but not returnable.
- **Secondary index** (`INDEX`). Searchable like the key, and also stored in
  payload so it is returned.
- **Payload** (everything else). Returned, never matched.

A searchable value (the key or an index) maps into a `2^key_bits` universe. `INT`
maps directly (range-checked). `TEXT` hashes through a deterministic FNV hash, so
a `TEXT` match is a *candidate*: collisions are possible but unlikely, and a
larger `key_bits` lowers the rate. Client-side verification of `TEXT` matches is
a tracked TODO.

Payload columns are packed at ingest (int and real take 8 bytes, text takes a
2-byte length plus bytes) and decoded on the client. Every searchable column's
key is packed side by side in one match record,
`SearchableCount * ceil(key_bits/8)` bytes per row in schema order. A single-key
table has one searchable column, so its match record is byte-identical to a table
with no secondary index.

### Querying a secondary index

A query names one searchable column in its `WHERE`. At query time the engine
slices out that column's sub-key by its position among the searchable columns and
runs the exact same matcher on it. There is no extra ciphertext multiply and no
added multiplicative depth, so matching a secondary index costs the same as
matching the key and reveals no more to the operator. Only one condition per
query is evaluated; conjunctions (`col1 = a AND col2 = b`) parse but are not yet
evaluated under encryption.

## The matching algorithm

Matching is bit-sliced equality over SIMD slots. The match key is binary
expanded into `key_bits` slots per record, and many records are packed into the
slots of a single ciphertext. The query value is bit-expanded and tiled across
all slots, so the query travels as **one** ciphertext.

For each batch ciphertext the server computes, in parallel across the whole
batch:

1. **Per-bit difference.** `diff = query - key` (a `sub_plain`), then
   `sq = diff * diff` (a `square`). This gives `(q - k)^2`, which is 0 where bits
   match and 1 where they differ.
2. **Per-bit XNOR.** `eq = 1 - sq`, the per-bit equality indicator.
3. **AND across each record's bits.** A rotate-and-multiply tree of depth
   `log2(key_bits)` reduces the per-bit indicators into one equality indicator
   per record.
4. **Block masking and broadcast.** A plaintext mask blocks record starts, then
   a doubling masked broadcast spreads the indicator. This uses no plaintext
   multiply, so it spends no noise and causes no cross-block bleed.
5. **Retrieve.** For each payload plane, a `multiply_plain` by the packed
   payload, then a block-sum that stops at the bucket width
   (`core::BucketStride`), leaving one partial sum per result bucket. Only
   matching records' payloads survive, one per bucket.

The two SIMD slot rows are not merged with `rotate_columns`. Each bucket's
payload lands in one row at slot `bucket * stride`, and the client sums the two
rows' slots for that bucket.

### Why this is cheap

The whole scan costs only `1 + log2(key_bits)` ciphertext-times-ciphertext
multiplies per batch (the dominant FHE cost), regardless of how many records the
batch holds. At `key_bits = 16` that is multiplicative depth 5. The expensive
multiplies amortize across thousands of rows.

### Multiple results, LIMIT and OFFSET

A single equality can match more than one row, and `LIMIT`/`OFFSET` page through
those matches. Rows are partitioned into `result_buckets` buckets (default 16, a
power of two, at most `(poly/2)/key_bits`). The row that is the i-th of its key
goes to bucket `(Mix(key) + i) % result_buckets`, where `Mix` is a splitmix64
finalizer. Rows that share a key therefore land in distinct buckets, and
different keys spread evenly for dense packing.

Placement is purely local and computed at query time, so it changes nothing on
disk. A bucket collision can only happen between rows of the same key, and
because sharding is by key every row of a key lives on one shard, so placement is
deterministic per shard. The matcher always partitions into `result_buckets`
regardless of the query's `LIMIT`/`OFFSET`; setting `result_buckets = 1` opts
back into the single-bucket collapse, which is correct only when keys are unique.

All buckets share one ciphertext per plane, so the whole partition rides in one
result blob and the result size does not grow with `LIMIT`. On the client,
`crypto::DecryptResults` decodes every bucket. A per-bucket presence count
separates empty (0) from a clean single match (1) from a collision (>= 2).
Collided buckets are dropped and counted, and the CLI surfaces the count as a
warning.

`LIMIT` and `OFFSET` are then applied client-side as a skip and take over the
decoded clean rows, in bucket order and stable across queries. `LIMIT` counts
rows, not bucket slots, and `OFFSET` pages through matches. The default is
`LIMIT 1`, `OFFSET 0`. A key with up to `result_buckets` rows returns all of them
in one query; raise `result_buckets` to return more.

### Empty results

A no-match must look the same as a match to the operator. The backend appends a
"presence" ciphertext, the per-bucket match count `sum_r b_r`. On decrypt the
client reads it first and returns nothing for a zero-count bucket. A no-match is
therefore an encrypted empty result, and the operator never learns whether a
query matched.

### Combining shards

In a cluster each shard evaluates its own partial. `CombinePartials` adds the
shard partials plane-wise. For this to be correct the data must be sharded
disjoint (consistent hash); replicating the full set would double-count. A
secondary-index query combines the same way: rows are sharded by the primary key,
so each row still lives on exactly one shard and the plane-wise sum never
double-counts.

## FHE parameters

The parameters live once in config and are read by the crypto layer. Defaults:

| Parameter | Default | Notes |
| --- | --- | --- |
| `poly_modulus_degree` | 16384 | Required. The depth-5 pipeline exhausts the budget at 8192. |
| `coeff_modulus_bits` | `[60, 60, 60, 60, 60, 49]` | 349 bits, under the 438-bit degree-16384 limit. Leaves a measured ~52-bit budget. |
| `plain_modulus_bits` | 20 | |
| `key_bits` | 16 | Key universe is `2^key_bits`. Raising it deepens the AND tree and needs more primes. |

Tune against `examples/crypto_bench`, which times the SEAL primitives the
matcher uses (rotation, square, ciphertext multiply) at these parameters. The
reference backend test asserts a positive noise budget after the full pipeline.

## Keys

The client generates its own keys and registers the public material. Galois keys
are generated, but only the rotation steps the matcher actually uses
(power-of-two AND and broadcast steps plus the block-sum, roughly 17 keys).

At poly 16384 the reduced Galois set is about 125 MB, which is too big for one
gRPC message. The `Register` RPC streams it in 4 MB chunks, and the coordinator
forwards it to peers over a streaming `RegisterKeys` RPC. The relin keys are
about 7.5 MB and the public key about 1.5 MB. The client never sends its secret
key.

## Reference

The private matching builds on the homomorphic-encryption techniques described
in:

> Karaçay, L., Savaş, E., and Alptekin, H. (2020). Intrusion Detection Over
> Encrypted Network Data. *The Computer Journal*, 63(4), 604-619.
> doi:10.1093/comjnl/bxz111
