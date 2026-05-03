# Operations

## Production Shape

BFP currently runs on one Lightsail instance with Docker Compose. Keep this boring until there is a concrete reason to split it up.

- Canonical domain: `bigfluffypuffy.org`
- Redirect domain: `bigfuckingpuffy.org`
- Reverse proxy/TLS: Caddy
- App runtime: Puma serving the Roda app
- Database: local Postgres container
- Future jobs: Que worker and clock containers behind the `jobs` Compose profile

## Deploy

Deploys are manual for now:

```sh
ssh ubuntu@<lightsail-ip>
cd /srv/bfp
git pull --ff-only
docker compose -f compose.yaml -f compose.production.yaml up -d --build web caddy
```

Use a fast-forward pull only. If the production checkout has local changes, stop and inspect them instead of forcing the deploy.

## Health Checks

Basic checks after a deploy:

```sh
curl -s http://<lightsail-ip>/health
curl -I https://bigfluffypuffy.org/
curl -I https://bigfuckingpuffy.org/some/path
```

Expected results:

- `/health` returns `{"status":"ok"}`.
- `https://bigfluffypuffy.org/` returns `200`.
- `https://bigfuckingpuffy.org/...` redirects to the same path on `https://bigfluffypuffy.org/...`.

If local DNS looks stale after nameserver changes, compare against public resolvers:

```sh
dig @1.1.1.1 +short A bigfluffypuffy.org
dig @8.8.8.8 +short A bigfluffypuffy.org
```

## Useful Server Commands

```sh
docker compose -f compose.yaml -f compose.production.yaml ps
docker compose -f compose.yaml -f compose.production.yaml logs --tail=100 web
docker compose -f compose.yaml -f compose.production.yaml logs --tail=100 caddy
docker compose -f compose.yaml -f compose.production.yaml restart web
docker compose -f compose.yaml -f compose.production.yaml up -d --force-recreate caddy
```

Recreate Caddy when DNS has just settled and TLS issuance needs a clean retry.

## Secrets

Production secrets live outside git. The production `.env` file should stay on the server and should never be committed.

Near-term secret needs:

- Production database password
- Future AWS credentials or instance role for backups
- Future email/API tokens for contact forms or notifications

## Backups

This is not implemented yet. The first acceptable backup plan is:

- Nightly `pg_dump` from the Postgres container.
- Encrypt the dump before it leaves the instance.
- Store it in a low-cost S3 bucket.
- Keep at least 7 daily and 4 weekly restore points.
- Test restore into a throwaway local database before trusting the system.

Lightsail snapshots are useful for machine recovery, but they are not a substitute for database dumps.

## Upgrade Posture

Prefer small, reversible upgrades:

- Upgrade Ruby locally and in CI first.
- Update the Docker base image after the test suite passes.
- Deploy after CI is green.
- Keep the old image available until the new container has passed health checks.

## Cost Guardrails

Do not add paid managed services by default. Revisit when there is real pressure from traffic, reliability, or operational burden.

Good early costs:

- One Lightsail instance
- Route 53 hosted zones
- S3 backup storage

Deferred until needed:

- Managed Postgres
- Load balancers
- CDN
- Separate worker instances
- Observability platforms
