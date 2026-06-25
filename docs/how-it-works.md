# How it works

OpaqueDB matches a query against stored rows without decrypting either. This
page explains the matching algorithm, the data model it runs over, and the FHE
parameters that make it fit.

## The data model

A schema is one `CREATE TABLE name (col TYPE [KEY], ...)`. Types are `INT`,
`REAL`, and `TEXT`. Exactly one column is the match `KEY` (`INT` or `TEXT`, not
`REAL`).

- The match key maps into a `2^key_bits` universe. `INT` maps directly
  (range-checked). `TEXT` hashes through a deterministic FNV hash, so a `TEXT`
  match is a *candidate*: collisions are possible but unlikely, and a larger
  `key_bits` lowers the rate. Client-side verification of `TEXT` matches is a
  tracked TODO.
- Payload columns are returned, not matched. They are packed at ingest (int and
  real take 8 bytes, text takes a 2-byte length plus bytes) and decoded on the
  client.

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
   payload, then a block-sum into block 0. Only the matching record's payload
   survives.

The two SIMD slot rows are not merged with `rotate_columns`. The matched payload
lands in block 0 of one row, and the client sums the two row-0 blocks.

### Why this is cheap

The whole scan costs only `1 + log2(key_bits)` ciphertext-times-ciphertext
multiplies per batch (the dominant FHE cost), regardless of how many records the
batch holds. At `key_bits = 16` that is multiplicative depth 5. The expensive
multiplies amortize across thousands of rows.

### Empty results

A no-match must look the same as a match to the operator. The backend appends a
"presence" ciphertext, `sum_r b_r`, the match count. On decrypt the client reads
this first and returns nothing at zero. A no-match is therefore an encrypted
empty result, and the operator never learns whether a query matched.

### Combining shards

In a cluster each shard evaluates its own partial. `CombinePartials` adds the
shard partials plane-wise. For this to be correct the data must be sharded
disjoint (consistent hash); replicating the full set would double-count.

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
