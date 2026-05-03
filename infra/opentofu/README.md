# OpenTofu

This directory will manage Lightsail, Route 53, S3 backup storage, and IAM once AWS credentials are ready.

V1 target resources:

- Lightsail 2 GB Linux instance in `us-west-2`
- static IPv4 attached to the instance
- Route 53 hosted zones for BFP domains
- S3 bucket for encrypted Postgres dumps
- IAM policy/user or role for backups and deploy automation
