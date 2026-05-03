# Ansible

This directory provisions configuration on the Lightsail box.

Current responsibilities:

- Manage the production `.env` fire parser settings.
- Install least-privilege Bedrock parser access keys created by OpenTofu.
- Keep paid parsing and Sonnet escalation disabled by default.

Planned responsibilities:

- Install Docker
- create deploy user
- harden SSH
- configure firewall
- install project systemd units
- install nightly Postgres dump timer

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

The playbook writes these values into `/srv/bfp/.env` with mode `0600`. It leaves `LLM_PARSE_ENABLED=false`, `LLM_ESCALATION_ENABLED=false`, and `FIRE_AUTO_POLL_ENABLED=false` unless you intentionally override them.
