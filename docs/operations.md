# Operations

## Production Shape

BFP currently runs on one Lightsail instance with Docker Compose. Keep this boring until there is a concrete reason to split it up.

- Canonical domain: `bigfluffypuffy.org`
- Redirect domain: `bigfuckingpuffy.org`
- Reverse proxy/TLS: Caddy
- App runtime: Puma serving the Roda app
- Database: local Postgres container
- Future jobs: Que worker and clock containers behind the `jobs` Compose profile

Caddy intentionally serves HTTPS over HTTP/1.1 and HTTP/2 only. The production
host publishes TCP 443, but not UDP 443; disabling HTTP/3 keeps Caddy from
advertising an unavailable `h3` path to clients behind networks that block UDP
443. HTTPS responses also send `Alt-Svc: clear` so browsers with a previously
cached HTTP/3 alternative service entry can discard it. Caddy access logging is
enabled while diagnosing Chrome/Zscaler connection failures.

## Deploy

Deploys are manual for now. Use the guarded helper from your local checkout:

```sh
bin/prod-deploy
```

Run migrations or reseed fire restriction sources only when needed:

```sh
bin/prod-deploy --migrate
bin/prod-deploy --migrate --seed
```

The helper aborts if the production checkout has local changes, fast-forwards
git, rebuilds only the `web` and `caddy` services, and runs public smoke checks.
It does not start the `worker` or `clock` services.

The underlying manual steps are:

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

Current secret flow:

- Bedrock parser credentials are created by OpenTofu in `infra/opentofu`.
- These credentials are created in the AWS account configured by `infra/opentofu/terraform.tfvars`, currently the account used by the local AWS CLI.
- The IAM user is restricted to the configured Haiku primary model, can subscribe only to that Haiku Marketplace product when Bedrock performs first-use enablement, and is explicitly denied other Bedrock model invocations.
- Ansible writes the generated key into `/srv/bfp/.env`.
- OpenTofu state contains the generated secret access key, so keep state private and do not commit local state files.

Apply the IAM configuration:

```sh
cd infra/opentofu
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu plan
tofu apply
```

Install the generated credentials on the Lightsail box:

```sh
ansible-playbook \
  -i infra/ansible/inventory.ini \
  infra/ansible/playbook.yml \
  -e bfp_aws_access_key_id="$(cd infra/opentofu && tofu output -raw bedrock_parser_access_key_id)" \
  -e bfp_aws_secret_access_key="$(cd infra/opentofu && tofu output -raw bedrock_parser_secret_access_key)"
```

Remaining secret needs:

- Production database password
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
