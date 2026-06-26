# Use cases

OpaqueDB fits any service where the *question* is more sensitive than the
*answer*. The operator runs a lookup over its own data and returns a result, but
never learns the value you searched for. Each design below maps onto the one
query OpaqueDB evaluates today: a private equality lookup on a key column,
`SELECT <cols> FROM <table> WHERE <key> = :param`, optionally paged with
`LIMIT`/`OFFSET`.

Keep the trust model in mind (see [Security](security.md)). OpaqueDB hides the
query value, not the fact that you connected. The operator still learns which
authenticated principal sent a query. Where a use case needs to hide *who* is
asking as well as *what*, add an anonymity layer above the database: an
anonymizing proxy, a mix network, or anonymous credentials in your application.

## Private weather

**The leak.** Weather APIs take a latitude and longitude or a city and country.
The operator can link the requesting IP or device to the location and build a
movement profile over time.

**With OpaqueDB.** Index forecasts by the geohash of each cell and have the
client compute the geohash locally. The client queries the geohash; the operator
returns the forecast without learning where the client is.

```sql
-- forecast.sql
CREATE TABLE forecast (
  geohash TEXT KEY,
  temperature INT,
  humidity INT,
  conditions TEXT
);
```

```console
$ opaquedb query 'SELECT temperature, conditions FROM forecast WHERE geohash = "u173zy"' \
    --schema forecast.sql
temperature=8 conditions=Drizzle
```

The geohash never leaves the client in the clear. Geohash length is a
privacy/utility knob: a shorter prefix covers a larger area and reveals less
about the exact point.

## Private messaging

**The leak.** End-to-end encryption (Signal, Threema, and most others) protects
message content, but the operator still sees metadata: who fetches messages,
from which conversation, and when. That social graph is often as sensitive as the
content.

**With OpaqueDB.** Store each conversation's messages under a channel id that
only the participants can derive, for example a per-conversation token from the
shared key. A client fetches its channel with a private lookup, so the operator
cannot tell which channel is being read or link two participants. Message bodies
stay end-to-end encrypted in the payload; OpaqueDB hides the access pattern over
them.

```sql
-- mailbox.sql
CREATE TABLE mailbox (
  channel TEXT KEY,
  seq INT,
  ciphertext TEXT
);
```

```console
$ opaquedb query 'SELECT seq, ciphertext FROM mailbox WHERE channel = :id LIMIT 50' \
    --schema mailbox.sql
```

`LIMIT` and `OFFSET` page through a backlog of messages in one query. This hides
which channel a client reads; it does not by itself hide that the client
connected. For full sender and recipient unlinkability, run it behind an
anonymizing transport.

## Threat intelligence

**The leak.** Analysts look up observables (file hashes, domains, IPs) in
services like VirusTotal. The lookup itself leaks intent. A Fortune 500 querying
a specific ransomware sample hints it may be under attack by that group;
searching internal project names against a leak corpus reveals what the company
is worried about.

**With OpaqueDB.** Index the intelligence by the observable and let analysts
query privately. The provider returns the verdict without learning which
indicator was checked, so a query can never be linked back to the asker's
situation.

```sql
-- iocs.sql
CREATE TABLE iocs (
  indicator TEXT KEY,
  verdict TEXT,
  family TEXT,
  first_seen INT
);
```

```console
$ opaquedb query 'SELECT verdict, family FROM iocs WHERE indicator = "<sha256>"' \
    --schema iocs.sql
verdict=malicious family=LockBit
```

The same shape covers searching a leaked-credential or breach corpus for your
own secret project names or domains, without revealing the search terms to the
intelligence vendor.

## More to build on

- **Credential and breach check.** Index a breach corpus by password or email
  hash and return whether, and where, it appeared. Unlike k-anonymity range
  checks that leak a hash prefix, OpaqueDB leaks nothing about the checked value.
- **URL and domain reputation.** A Safe Browsing style service that returns a
  reputation for a domain or URL hash without learning the user's browsing
  history.
- **Private contact discovery.** Check whether a contact is registered on a
  service without uploading the address book in the clear.

## Notes for building these

These designs share a few constraints from [How it works](how-it-works.md):

- **Searchable columns.** Each table has exactly one primary `KEY` and may add
  any number of secondary `INDEX` columns. A query matches on whichever column
  its `WHERE` names, one condition per query. Make every value you need to look
  up privately the `KEY` or an `INDEX`; the rest is returned payload. The primary
  key is matched but not stored in payload, so it cannot be projected back; an
  `INDEX` column is both searchable and returned.
- **TEXT keys are candidate matches.** A `TEXT` key is hashed into the
  `2^key_bits` universe (default `key_bits = 16`), so matches can collide. For
  high-cardinality keys such as hashes or ids, raise `key_bits` and verify the
  returned record client-side.
- **Many matches per key.** Set `crypto.result_buckets` and use `LIMIT`/`OFFSET`
  when one key maps to several rows, such as a message backlog or multiple
  sightings of one indicator.
- **Cost is a linear scan.** PIR scans every row. [Cluster](cluster.md) sharding
  spreads that scan across machines but does not reduce the total work. Size the
  corpus and the cluster accordingly.
