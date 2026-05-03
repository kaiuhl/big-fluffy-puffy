# Big Fluffy Puffy

Big Fluffy Puffy is a nonprofit web and data project for building fireless outdoor culture in the Pacific Northwest.

The codebase starts small: a mostly static public site, a lean Roda app for dynamic endpoints, Postgres for durable data, and background jobs for future fire-restriction checks.

## Stack

- Ruby 4.0+
- Bridgetown for static/content pages
- Roda for dynamic routes
- Sequel for database access and migrations
- Postgres for persistence
- Que for Postgres-backed background jobs
- RSpec for tests
- Docker Compose for local and single-box production runtime
- Caddy for TLS/reverse proxy
- OpenTofu + Ansible for infrastructure

## Local Setup

```sh
bundle install
cp .env.example .env
docker compose up postgres
bundle exec rake spec
bundle exec puma -C config/puma.rb
```

Then open `http://localhost:9292`.

## Exploring Data

Use the console for local data exploration:

```sh
bin/console
bin/console -e 'fire_counts'
bin/console -e 'latest_fetches'
```

Inside the console, handy helpers include `forests`, `forest("deschutes")`, `source("willamette-fire-info")`, `status("deschutes")`, `latest_fetches`, `latest_observations`, `review_candidates`, `review_forest("willamette")`, `review_queue`, `review_observation(123)`, `accept_observation(123)`, `reject_observation(123, "reason")`, and `auto_accept_observations`.

After a Bedrock-backed parse run, use `llm_costs` to see captured token usage and an estimated per-run cost:

```sh
bin/prod-console -e 'llm_costs'
```

To explore production data on the Lightsail box:

```sh
bin/prod-console
bin/prod-console -e 'fire_counts'
bin/prod-shell
```

Both production scripts default to `ubuntu@34.223.75.206` with `~/.ssh/bfp-lightsail.pem`; override with `BFP_HOST`, `BFP_USER`, `BFP_KEY`, or `BFP_PATH` if needed.

## Current Shape

This is intentionally just the foundation:

- `/health` returns a JSON health check.
- `/api/version` returns a minimal API identity payload.
- `/api/fire-restrictions/forests` returns the public fire-restriction status list.
- `/fire-restrictions` renders the public forest status table.
- Bridgetown content lives in `src/`.
- Infrastructure scaffolding lives in `infra/`.
- Fire-restriction ingestion jobs live in `jobs/`.

Seed and run fire-restriction ingestion manually:

```sh
bundle exec rake db:migrate
bundle exec rake que:migrate
bundle exec rake fire:sources:seed
bundle exec rake fire:poll_due
bundle exec rake fire:review:candidates
bundle exec rake 'fire:review:forest[willamette]'
bundle exec rake fire:review:list
bundle exec rake 'fire:review:show[123]'
bundle exec rake fire:review:auto_accept
bundle exec rake 'fire:review:accept[123]'
bundle exec rake 'fire:review:reject[123,wrong source]'
bundle exec rake fire:status:list
```

Automatic polling is off by default. During fire season, enable it explicitly with `FIRE_AUTO_POLL_ENABLED=true`; enable Bedrock parsing with `LLM_PARSE_ENABLED=true` only when you want changed pages parsed by the LLM. Sonnet escalation is separately off by default with `LLM_ESCALATION_ENABLED=false`; set it to `true` only for intentional escalation runs.

Run background workers explicitly when needed:

```sh
docker compose --profile jobs up worker clock
```

Secrets belong in environment variables, GitHub Actions secrets, or AWS secret stores. Never commit them.

Bedrock parser AWS credentials are managed in `infra/opentofu` as a least-privilege IAM user with Haiku-only invoke permissions. `infra/ansible` installs those credentials into the production `.env` on the Lightsail box.

## Project Notes

- [Architecture](docs/architecture.md)
- [Brand language](docs/brand-language.md)
- [Fire restrictions data inventory](docs/fire-restrictions-data-inventory.md)
- [Operations](docs/operations.md)
- [Site roadmap](docs/site-roadmap.md)
