# Cluster

OpaqueDB deploys as a sharded cluster of identical nodes. PIR requires a full
linear scan, and sharding spreads that scan across many machines. It improves
latency and throughput, not total work.

## How a clustered query runs

1. A client sends an encrypted query to any node.
2. That node becomes the coordinator. It evaluates its own shard
   (`Engine::EvaluateShard`, no combine) and fans the query out to every peer
   over the node-to-node `ShardService` (`Evaluate` + `RegisterKeys`).
3. Each peer evaluates its shard and returns an encrypted partial.
4. The coordinator combines the partials plane-wise (`CombinePartials`) and
   returns the encrypted result.

Any node can be the coordinator; each coordinates equally. The query keys are
forwarded to every peer when the client registers; peers are reached at
`server.advertise`, so set it when binding a wildcard.

**Data must be sharded disjoint** by a consistent hash of the primary key.
Replicating the full set would double-count in the combine. A secondary-index
query fans out and combines exactly like a key query, because every row still
lives on one shard. Use `load --shard-id N --shard-nodes a,b,c` to load a single
node's shard.

## Coordination with etcd

Cluster membership and leadership run on etcd. `cluster.enabled` (default
`false`) gates joining. `ClusterManager::Tick()` does lease and keepalive,
membership, CAS leader election, and shard-map publish; in production this runs
on a thread.

etcd auth and TLS are configured under `[cluster]`. See
[Configuration](configuration.md#cluster). `etcd-cpp-apiv3` is vendored as an
overlay port, core-only (no cpprestsdk).

## Trust domain

Node-to-node traffic is its own trust domain, separate from client auth. Peer
channels present the cluster certificate (`cluster.tls_cert`/`tls_key`) and
verify peers against the cluster CA (`cluster.ca_cert`). A clustered node refuses
to start without cluster mTLS or server TLS, unless `cluster.allow_insecure` is
set for local development.

## Docker Compose demo

The setup in `docker/` brings up one etcd and three nodes that elect a leader,
load a disjoint shard each, and answer a cross-shard private query.

```sh
docker compose -f docker/docker-compose.yml up --build -d

docker compose -f docker/docker-compose.yml run --rm tools \
  query 'SELECT country, temperature FROM weather WHERE city = "Santiago"' \
  --target node1:50051
```

Any node can be the `--target`; each coordinates the query across all shards.

## Key distribution

The reduced Galois key set is about 125 MB at poly 16384, too large for one gRPC
message. `Register` streams it in 4 MB chunks and the coordinator forwards it to
peers over a streaming `RegisterKeys` RPC. Key distribution is the coordinator's
job. The production path is a shared object store (`BlobStoreConfig`, MinIO or
S3), a tracked TODO.
