# AGENTS.md

## Project Snapshot

Big Fluffy Puffy is a nonprofit web and data project for fireless outdoor culture in the Pacific Northwest.

The app is intentionally small:

- Public web app: Roda Rack app served by Puma.
- Static/content layer: Bridgetown content in `src/`.
- Persistence: Postgres via Sequel and `Sequel::Model`.
- Background jobs: Que with Postgres-backed jobs.
- Runtime: Docker Compose on a single Lightsail box behind Caddy.
- First durable data domain: national forest fire-restriction source monitoring.

Useful docs:

- `README.md`: local setup and common commands.
- `docs/operations.md`: deploy and server operations.
- `docs/architecture.md`: current production shape.
- `docs/fire-restrictions-data-inventory.md`: source inventory and ingestion rationale.

## Local Development

Use `mise` for Ruby. The macOS system Ruby is too old for this app.

```sh
mise exec -- bundle install
mise exec -- bundle exec rake spec
mise exec -- bundle exec standardrb
mise exec -- bundle exec puma -C config/puma.rb
```

Local Postgres through Docker:

```sh
docker compose up -d postgres
mise exec -- bundle exec rake db:migrate
mise exec -- bundle exec rake que:migrate
mise exec -- bundle exec rake fire:sources:seed
```

Database integration specs are opt-in:

```sh
RUN_DB_SPECS=true mise exec -- bundle exec rspec spec/bfp/fire_restrictions/database_integration_spec.rb
```

Normal specs intentionally skip those DB integration examples unless `RUN_DB_SPECS=true`.

## Console And Shell Helpers

Local app console:

```sh
bin/console
bin/console -e 'fire_counts'
bin/console -e 'latest_fetches'
```

The console preloads `config/boot` and `bfp/fire_restrictions` when the database is available. It adds helpers: `app_env`, `database_url`, `fire_counts`, `forests`, `forest("deschutes")`, `source("willamette-fire-info")`, `status("deschutes")`, `latest_fetches`, `latest_observations`, and `llm_costs`.

Production console and shell:

```sh
bin/prod-console
bin/prod-console -e 'fire_counts'
bin/prod-shell
```

Both production scripts default to `ubuntu@34.223.75.206`, `~/.ssh/bfp-lightsail.pem`, and `/srv/bfp`. Override with `BFP_HOST`, `BFP_USER`, `BFP_KEY`, or `BFP_PATH` if needed.

## Fire Restrictions

Current public endpoints:

- `GET /api/fire-restrictions/forests`
- `GET /fire-restrictions`

Core fire-restriction files:

- `config/fire_restriction_sources.yml`: source catalog.
- `db/migrations/001_fire_restrictions.rb`: fire data schema.
- `lib/bfp/fire_restrictions/`: fetch, extract, parse, validate, resolve, present.
- `lib/bfp/llm/`: parser interface, fake parser, Bedrock parser.
- `jobs/fire_restriction_jobs.rb`: Que jobs.

The catalog currently seeds:

- 26 land units total.
- 23 active land units.
- 111 sources total.
- 99 active sources.

Cost safety matters. Defaults should stay manual and cheap:

- `LLM_PARSE_ENABLED=false`
- `FIRE_AUTO_POLL_ENABLED=false`

Do not start automatic polling or enable Bedrock parsing unless the user explicitly asks. Manual fetches can still persist source documents with LLM parsing off.

Manual commands:

```sh
mise exec -- bundle exec rake fire:sources:seed
mise exec -- bundle exec rake 'fire:poll[willamette-fire-info]'
mise exec -- bundle exec rake fire:poll_due
mise exec -- bundle exec rake fire:review:list
mise exec -- bundle exec rake 'fire:review:accept[123]'
mise exec -- bundle exec rake fire:status:list
```

To intentionally run paid parsing:

```sh
LLM_PARSE_ENABLED=true mise exec -- bundle exec rake fire:poll_due
```

After Bedrock-backed parsing, inspect captured token usage and estimated cost with:

```sh
bin/prod-console -e 'llm_costs'
```

## Production

Production is a single Lightsail instance:

- Domain: `bigfluffypuffy.org`
- Current IP from DNS: `34.223.75.206`
- SSH user: `ubuntu`
- App path: `/srv/bfp`
- Local SSH key, if present: `~/.ssh/bfp-lightsail.pem`
- Compose files: `compose.yaml` plus `compose.production.yaml`

SSH:

```sh
ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206
```

Before deploying, check the production checkout:

```sh
cd /srv/bfp
git status --short
git rev-parse --short HEAD
```

Use fast-forward pulls only. If production has local changes, stop and inspect.

Deploy web/Caddy:

```sh
cd /srv/bfp
git pull --ff-only
docker compose -f compose.yaml -f compose.production.yaml up -d --build web caddy
```

Run migrations and seed:

```sh
docker compose -f compose.yaml -f compose.production.yaml run --rm web bundle exec rake db:migrate
docker compose -f compose.yaml -f compose.production.yaml run --rm web bundle exec rake que:migrate
docker compose -f compose.yaml -f compose.production.yaml run --rm web bundle exec rake fire:sources:seed
```

Manual no-cost smoke poll:

```sh
docker compose -f compose.yaml -f compose.production.yaml run --rm -e LLM_PARSE_ENABLED=false web bundle exec rake 'fire:poll[deschutes-central-oregon-restrictions]'
docker compose -f compose.yaml -f compose.production.yaml run --rm -e LLM_PARSE_ENABLED=false web bundle exec rake 'fire:poll[willamette-fire-info]'
```

Confirm only intended containers are running:

```sh
docker compose -f compose.yaml -f compose.production.yaml ps
```

For non-season manual mode, `worker` and `clock` should not be running.

If the user explicitly wants summer automatic polling:

```sh
docker compose -f compose.yaml -f compose.production.yaml --profile jobs up -d --build worker clock
```

Only do this with `FIRE_AUTO_POLL_ENABLED=true` intentionally set in production `.env`.

## Production Smoke Checks

```sh
curl -sS https://bigfluffypuffy.org/health
curl -I -sS https://bigfluffypuffy.org/fire-restrictions
curl -sS https://bigfluffypuffy.org/api/fire-restrictions/forests
```

Helpful production DB count check:

```sh
docker compose -f compose.yaml -f compose.production.yaml run --rm web bundle exec ruby -rjson -e 'require_relative "config/boot"; require "bfp/fire_restrictions"; puts JSON.pretty_generate({land_units: BFP::FireRestrictions::LandUnit.count, active_land_units: BFP::FireRestrictions::LandUnit.where(active: true).count, sources: BFP::FireRestrictions::RestrictionSource.count, active_sources: BFP::FireRestrictions::RestrictionSource.where(active: true).count, fetches: BFP::FireRestrictions::SourceFetch.count, documents: BFP::FireRestrictions::SourceDocument.count, observations: BFP::FireRestrictions::RestrictionObservation.count, statuses: BFP::FireRestrictions::RestrictionStatus.count})'
```

Last known production smoke state after deploying fire ingestion:

- `https://bigfluffypuffy.org/health` returned ok.
- `/api/fire-restrictions/forests` returned 23 forests.
- Deschutes ArcGIS source resolved to `none / allowed`, `auto_accepted`.
- Willamette HTML source persisted with `unknown / needs_review` while `LLM_PARSE_ENABLED=false`.
- Production `.env` had `LLM_PARSE_ENABLED=false` and `FIRE_AUTO_POLL_ENABLED=false`.

## Coding Notes

- Prefer existing Roda, Sequel, Que, and plain Ruby patterns.
- Use `Sequel::Model` for database-backed fire restriction records.
- Wrap JSONB values with `BFP::FireRestrictions::Jsonb.wrap(...)` before persisting Ruby hashes/arrays to Postgres JSONB columns.
- Do not make live AWS Bedrock calls in tests. Use `FakeParserClient`.
- Keep fetched raw content in Postgres for now, deduped by `content_hash`.
- ArcGIS geometry is stored as JSONB. Do not add PostGIS unless the product genuinely needs geometry queries.
- Keep LLM parsing conservative: unsupported fields should become `unknown`, and non-ArcGIS parsed observations should require human review before public trust.
- Evidence quotes for HTML/PDF must match extracted text after whitespace normalization. ArcGIS evidence can be concise attribute summaries.
- Do not commit secrets or production `.env`.
- Do not stage unrelated local files. In current local worktrees, `public/images/` may be untracked and unrelated.

## Git

The user is currently comfortable committing directly to `main`; do not open PRs unless asked.

Recommended flow:

```sh
git status --short
mise exec -- bundle exec standardrb
mise exec -- bundle exec rake spec
git add <related files only>
git commit -m "<concise message>"
git push origin main
```

After pushing deployable runtime changes, deploy to the box only when the user asks.
