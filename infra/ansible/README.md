# Ansible

This directory provisions configuration on the Lightsail box.

Current responsibilities:

- Manage the production `.env` fire parser settings.
- Install least-privilege Bedrock parser access keys created by OpenTofu.
- Install the optional NPS Data API key used by national park alert sources.
- Keep paid parsing, automatic polling, and Sonnet escalation disabled by default.
- Install the nightly Postgres dump timer: AWS CLI v2, write-only backup
  credentials in `/etc/bfp/pg-backup.env`, and the `bfp-pg-backup`
  systemd service and timer (tasks tagged `pg_backup`; see
  `docs/postgres-backup-spec.md`).

Planned responsibilities:

- Install Docker
- create deploy user
- harden SSH
- configure firewall

## Inventory

Create a local inventory from the example:

```sh
cp infra/ansible/inventory.example.ini infra/ansible/inventory.ini
```

`inventory.ini` is ignored; commit only the example and keep private host overrides local.

## Configure Bedrock Parser Credentials

From the repo root after `infra/opentofu` has been applied:

```sh
ansible-playbook \
  -i infra/ansible/inventory.ini \
  infra/ansible/playbook.yml \
  -e bfp_aws_access_key_id="$(cd infra/opentofu && tofu output -raw bedrock_parser_access_key_id)" \
  -e bfp_aws_secret_access_key="$(cd infra/opentofu && tofu output -raw bedrock_parser_secret_access_key)"
```

The playbook writes these values into `/srv/bfp/.env` with mode `0600`. It leaves `LLM_PARSE_ENABLED=false`, `LLM_ESCALATION_ENABLED=false`, and `FIRE_AUTO_POLL_ENABLED=false` unless you intentionally override them. It also writes the production clock cadence defaults `CLOCK_INTERVAL_SECONDS=604800` and `FIRE_POLL_BATCH_SIZE=150`.

To configure National Park Service alert polling, pass the free NPS Data API key
as `-e bfp_nps_api_key=...`. The playbook writes it as `NPS_API_KEY` and does
not enable automatic polling.

## Configure Postgres Backups

From the repo root after `infra/opentofu` has been applied:

```sh
ansible-playbook \
  -i infra/ansible/inventory.ini \
  infra/ansible/playbook.yml \
  --tags pg_backup \
  -e bfp_pg_backup_bucket="$(cd infra/opentofu && tofu output -raw pg_backup_bucket)" \
  -e bfp_pg_backup_access_key_id="$(cd infra/opentofu && tofu output -raw pg_backup_access_key_id)" \
  -e bfp_pg_backup_secret_access_key="$(cd infra/opentofu && tofu output -raw pg_backup_secret_access_key)"
```

The backup credentials go to `/etc/bfp/pg-backup.env` (root, `0600`), not
`/srv/bfp/.env`, so app containers never see them. The timer runs the dump
script from the production checkout, so the script itself deploys with
`git pull`.
