# Big Fluffy Puffy

Big Fluffy Puffy is a Ruby-first nonprofit web and data project for building fireless outdoor culture in the Pacific Northwest.

The codebase starts small: a mostly static public site, a lean Roda app for dynamic endpoints, Postgres for durable data, and background jobs for future fire-restriction checks.

## Stack

- Ruby 3.4+
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

## Current Shape

This is intentionally just the foundation:

- `/health` returns a JSON health check.
- `/api/version` returns a minimal API identity payload.
- Bridgetown content lives in `src/`.
- Infrastructure scaffolding lives in `infra/`.
- Background job placeholders live in `jobs/`.

Secrets belong in environment variables, GitHub Actions secrets, or AWS secret stores. Never commit them.
