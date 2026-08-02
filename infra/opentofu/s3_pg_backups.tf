locals {
  pg_backup_user_name   = coalesce(var.pg_backup_user_name, "bfp-${var.environment}-pg-backup")
  pg_backup_bucket_name = coalesce(var.pg_backup_bucket_name, "bfp-${var.environment}-pg-backups-${var.aws_account_id}")

  # The backup credentials on the box may write only under this prefix.
  pg_backup_prefix = "postgres"
}

resource "aws_s3_bucket" "pg_backups" {
  bucket = local.pg_backup_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is the tamper guard: the box's write-only credentials can
# overwrite an object but never purge its versions, so history survives a
# compromised host for the noncurrent-version retention window below.
resource "aws_s3_bucket_versioning" "pg_backups" {
  bucket = aws_s3_bucket.pg_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pg_backups" {
  bucket = aws_s3_bucket.pg_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pg_backups" {
  bucket = aws_s3_bucket.pg_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "pg_backups" {
  bucket = aws_s3_bucket.pg_backups.id

  rule {
    id     = "retain-dumps-one-year"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_iam_user" "pg_backup" {
  name = local.pg_backup_user_name
  path = "/bfp/"
}

resource "aws_iam_access_key" "pg_backup" {
  user = aws_iam_user.pg_backup.name
}

# Write-only on purpose: the box can add dumps but cannot read, list, or
# delete them, so these credentials leaking with the host does not expose
# or endanger backup history.
data "aws_iam_policy_document" "pg_backup" {
  statement {
    sid    = "AllowWriteDumps"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload"
    ]

    resources = [
      "${aws_s3_bucket.pg_backups.arn}/${local.pg_backup_prefix}/*"
    ]
  }
}

resource "aws_iam_policy" "pg_backup" {
  name        = "bfp-${var.environment}-pg-backup-write-only"
  description = "Write-only S3 access for BFP ${var.environment} Postgres dump uploads."
  path        = "/bfp/"
  policy      = data.aws_iam_policy_document.pg_backup.json
}

resource "aws_iam_user_policy_attachment" "pg_backup" {
  user       = aws_iam_user.pg_backup.name
  policy_arn = aws_iam_policy.pg_backup.arn
}
