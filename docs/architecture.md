# Architecture

## Baseline

BFP runs as a single cheap Lightsail VPS until traffic or operational needs justify more services.

The production box runs Docker Compose:

- `caddy`: public HTTP/TLS reverse proxy
- `web`: Roda/Bridgetown Rack app served by Puma
- `worker`: Que worker process
- `clock`: lightweight scheduler that enqueues recurring checks
- `postgres`: application database

## Ruby Application

Bridgetown owns mostly static public content. Roda owns dynamic routes, health checks, and future APIs. Sequel provides database access without pulling in Rails. Que stores jobs in Postgres so job state and application data back up together.

## Future Data Platform

The first durable data domain will track fire-restriction sources and snapshots:

- source metadata
- fetched pages
- parsed restriction state
- content hashes
- check history

Raw fetched documents can start on disk and move to S3 once volume or retention needs make that worthwhile.

## Cost Posture

The v1 target is one 2 GB Lightsail instance, Route 53 DNS, Lightsail snapshots, and nightly encrypted Postgres dumps to S3. Managed Postgres, a CDN, and load balancers are deferred until they solve a real problem.
