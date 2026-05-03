# Ansible

This directory will provision the Lightsail box after OpenTofu creates it.

V1 responsibilities:

- install Docker
- create deploy user
- harden SSH
- configure firewall
- install project systemd units
- install nightly Postgres dump timer
