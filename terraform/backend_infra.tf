# S3 Bucket for Remote Terraform State
# checkov:skip=CKV_AWS_18:Access logging not required for state storage bucket
# checkov:skip=CKV_AWS_144:Cross-region replication not required for single-region lab
# checkov:skip=CKV_AWS_145:KMS CMK not required, AES256 server-side encryption is sufficient
# checkov:skip=CKV2_AWS_62:Event notifications not required for terraform state bucket
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "forensic-custody-tfstate-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Environment = "Management"
    Project     = "forensic-custody-api"
    ManagedBy   = "Terraform"
  }
}

# Enable Versioning for State History Recovery
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rule to clean up non-current state versions after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Server-Side Encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all Public Access to the State Bucket
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Table for Distributed State Locking
# checkov:skip=CKV_AWS_119:Default AWS-managed encryption is sufficient for transient lock IDs
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "forensic-custody-tfstate-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Environment = "Management"
    Project     = "forensic-custody-api"
    ManagedBy   = "Terraform"
  }
}
