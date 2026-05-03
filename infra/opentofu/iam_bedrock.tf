locals {
  bedrock_parser_user_name = coalesce(var.bedrock_parser_user_name, "bfp-${var.environment}-bedrock-parser")

  bedrock_primary_foundation_model_id    = replace(var.bedrock_primary_model_id, "/^global\\./", "")
  bedrock_escalation_foundation_model_id = replace(var.bedrock_escalation_model_id, "/^global\\./", "")

  bedrock_primary_inference_profile_arn = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}:${var.aws_account_id}:inference-profile/${var.bedrock_primary_model_id}"
  bedrock_primary_regional_model_arn    = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/${local.bedrock_primary_foundation_model_id}"
  bedrock_primary_global_model_arn      = "arn:${data.aws_partition.current.partition}:bedrock:::foundation-model/${local.bedrock_primary_foundation_model_id}"

  bedrock_escalation_inference_profile_arn = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}:${var.aws_account_id}:inference-profile/${var.bedrock_escalation_model_id}"
  bedrock_escalation_regional_model_arn    = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/${local.bedrock_escalation_foundation_model_id}"
  bedrock_escalation_global_model_arn      = "arn:${data.aws_partition.current.partition}:bedrock:::foundation-model/${local.bedrock_escalation_foundation_model_id}"
}

resource "aws_iam_user" "bedrock_parser" {
  name = local.bedrock_parser_user_name
  path = "/bfp/"
}

resource "aws_iam_access_key" "bedrock_parser" {
  user = aws_iam_user.bedrock_parser.name
}

data "aws_iam_policy_document" "bedrock_parser" {
  statement {
    sid    = "AllowPrimaryInferenceProfile"
    effect = "Allow"

    actions = [
      "bedrock:InvokeModel"
    ]

    resources = [
      local.bedrock_primary_inference_profile_arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "AllowPrimaryRegionalFoundationModelViaProfile"
    effect = "Allow"

    actions = [
      "bedrock:InvokeModel"
    ]

    resources = [
      local.bedrock_primary_regional_model_arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }

    condition {
      test     = "StringEquals"
      variable = "bedrock:InferenceProfileArn"
      values   = [local.bedrock_primary_inference_profile_arn]
    }
  }

  statement {
    sid    = "AllowPrimaryGlobalFoundationModelViaProfile"
    effect = "Allow"

    actions = [
      "bedrock:InvokeModel"
    ]

    resources = [
      local.bedrock_primary_global_model_arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["unspecified"]
    }

    condition {
      test     = "StringEquals"
      variable = "bedrock:InferenceProfileArn"
      values   = [local.bedrock_primary_inference_profile_arn]
    }
  }

  statement {
    sid    = "AllowPrimaryModelMarketplaceSubscriptionViaBedrock"
    effect = "Allow"

    actions = [
      "aws-marketplace:Subscribe",
      "aws-marketplace:ViewSubscriptions"
    ]

    resources = ["*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws-marketplace:ProductId"
      values   = [var.bedrock_primary_marketplace_product_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:CalledViaLast"
      values   = ["bedrock.amazonaws.com"]
    }
  }

  statement {
    sid    = "DenyAllOtherBedrockModelInvocations"
    effect = "Deny"

    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]

    not_resources = [
      local.bedrock_primary_inference_profile_arn,
      local.bedrock_primary_regional_model_arn,
      local.bedrock_primary_global_model_arn
    ]
  }

  statement {
    sid    = "DenyEscalationModelInvocations"
    effect = "Deny"

    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]

    resources = [
      local.bedrock_escalation_inference_profile_arn,
      local.bedrock_escalation_regional_model_arn,
      local.bedrock_escalation_global_model_arn
    ]
  }
}

resource "aws_iam_policy" "bedrock_parser" {
  name        = "bfp-${var.environment}-bedrock-parser-haiku-only"
  description = "Least-privilege Haiku-only Bedrock parser permissions for BFP ${var.environment}."
  path        = "/bfp/"
  policy      = data.aws_iam_policy_document.bedrock_parser.json
}

resource "aws_iam_user_policy_attachment" "bedrock_parser" {
  user       = aws_iam_user.bedrock_parser.name
  policy_arn = aws_iam_policy.bedrock_parser.arn
}
