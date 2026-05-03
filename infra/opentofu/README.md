# OpenTofu

This directory manages AWS resources that should be rebuildable from the repo.

Current resources:

- IAM user for the production app's Bedrock parser credentials.
- Haiku-only `bedrock:InvokeModel` policy for the primary parser model.
- Explicit deny for every other Bedrock model invocation, including the configured Sonnet escalation model.

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

The AWS provider is pinned to `aws_account_id`, so OpenTofu will refuse to apply if your active AWS credentials point at a different account.

## Production App Credentials

After apply, print the app environment lines:

```sh
tofu output -raw bedrock_parser_env
```

Those lines are intended for the production `.env` file on the Lightsail box.

Important: `aws_iam_access_key.bedrock_parser.secret` is stored in OpenTofu state. Keep local state private. Before this repo manages more production infrastructure, move state to a locked/encrypted remote backend such as S3 with state locking.

## Bedrock Model Access

IAM permissions are necessary but may not be sufficient on a fresh AWS account. If Bedrock returns a model-access error after these credentials are installed, enable access for the Anthropic Haiku model in the AWS Bedrock console for `us-west-2`.
