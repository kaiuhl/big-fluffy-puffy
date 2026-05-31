# OpenTofu

This directory manages AWS resources that should be rebuildable from the repo.

Current resources:

- IAM user for the production app's Bedrock parser credentials.
- Least-privilege `bedrock:InvokeModel` policy for the configured primary parser model and configured escalation parser model.
- Scoped AWS Marketplace subscribe/view permissions for the Haiku 4.5 Bedrock product, only when called through Bedrock for first-use model enablement.
- Explicit deny for every other Bedrock model invocation.

Planned resources:

- Lightsail 2 GB Linux instance in `us-west-2`
- static IPv4 attached to the instance
- Route 53 hosted zones for BFP domains
- S3 bucket for encrypted Postgres dumps

## One-Time Setup

Use AWS credentials for the production account, then create a local tfvars file:

```sh
cd infra/opentofu
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` is ignored because it can contain account-specific configuration.

## Apply

```sh
cd infra/opentofu
tofu init
tofu plan
tofu apply
```

The AWS provider is pinned to `aws_account_id`, so OpenTofu will refuse to apply if your active AWS credentials point at a different account. This should be the AWS account that owns the repo-managed Bedrock parser credentials; it does not have to be the same account that currently owns the manually created Lightsail instance.

## Production App Credentials

After apply, print the app environment lines:

```sh
tofu output -raw bedrock_parser_env
```

Those lines are intended for the production `.env` file on the Lightsail box.

Important: `aws_iam_access_key.bedrock_parser.secret` is stored in OpenTofu state. Keep local state private. Before this repo manages more production infrastructure, move state to a locked/encrypted remote backend such as S3 with state locking.

## Bedrock Model Access

IAM permissions are necessary but may not be sufficient on a fresh AWS account. Anthropic models require the first-time use case form, and third-party Bedrock models may create an AWS Marketplace subscription on first invocation.

This configuration allows the production parser identity to subscribe only to the configured Haiku 4.5 product ID through Bedrock. It allows invocation of the configured primary and escalation inference profiles, and denies every other Bedrock model. It does not grant broad Marketplace access. If the escalation model requires separate account-level model access or subscription, grant that in Bedrock before enabling production escalation.
