variable "aws_region" {
  type        = string
  description = "AWS region for BFP infrastructure."
  default     = "us-west-2"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID that owns BFP production infrastructure. The provider refuses to apply to any other account."
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "production"
}

variable "default_tags" {
  type        = map(string)
  description = "Default tags applied to AWS resources created by this configuration."
  default = {
    Project   = "BFP"
    ManagedBy = "OpenTofu"
  }
}

variable "bedrock_parser_user_name" {
  type        = string
  description = "IAM user name for the app's Bedrock parser credentials."
  default     = null
}

variable "bedrock_primary_model_id" {
  type        = string
  description = "Primary Bedrock inference profile model ID allowed for the app parser."
  default     = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "bedrock_escalation_model_id" {
  type        = string
  description = "Escalation model ID that this IAM identity explicitly cannot invoke."
  default     = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
}
