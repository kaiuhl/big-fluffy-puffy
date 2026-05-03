output "aws_account_id" {
  description = "AWS account ID OpenTofu applied against."
  value       = data.aws_caller_identity.current.account_id
}

output "bedrock_parser_user_name" {
  description = "IAM user that owns the app's Bedrock parser access key."
  value       = aws_iam_user.bedrock_parser.name
}

output "bedrock_parser_access_key_id" {
  description = "Access key ID for the app's least-privilege Bedrock parser credentials."
  value       = aws_iam_access_key.bedrock_parser.id
}

output "bedrock_parser_secret_access_key" {
  description = "Secret access key for the app's least-privilege Bedrock parser credentials. This is also stored in OpenTofu state."
  value       = aws_iam_access_key.bedrock_parser.secret
  sensitive   = true
}

output "bedrock_parser_env" {
  description = "Environment lines for the production app .env. This contains secrets and is also stored in OpenTofu state."
  value       = <<-ENV
AWS_ACCESS_KEY_ID=${aws_iam_access_key.bedrock_parser.id}
AWS_SECRET_ACCESS_KEY=${aws_iam_access_key.bedrock_parser.secret}
AWS_REGION=${var.aws_region}
LLM_PROVIDER=bedrock
LLM_PARSE_ENABLED=false
LLM_ESCALATION_ENABLED=false
BEDROCK_PRIMARY_MODEL_ID=${var.bedrock_primary_model_id}
BEDROCK_ESCALATION_MODEL_ID=${var.bedrock_escalation_model_id}
ENV
  sensitive   = true
}
