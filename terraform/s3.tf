resource "aws_s3_bucket" "evidence" {
  #checkov:skip=CKV_AWS_144:Accepted risk — see docs/adr/0002-s3-security-scope.md
  #checkov:skip=CKV2_AWS_62:Accepted risk — see docs/adr/0002-s3-security-scope.md
  #checkov:skip=CKV2_AWS_61:Accepted risk — see docs/adr/0002-s3-security-scope.md
  #checkov:skip=CKV_AWS_145:Accepted risk — see docs/adr/0002-s3-security-scope.md
  bucket = "forensic-custody-evidence-${data.aws_caller_identity.current.account_id}"

  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object_lock_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 1
    }
  }
}

resource "aws_s3_bucket" "evidence_logs" {
  #checkov:skip=CKV_AWS_144:Accepted risk — see docs/adr/0002-s3-security-scope.md
  #checkov:skip=CKV2_AWS_62:Accepted risk — see docs/adr/0002-s3-security-scope.md
  #checkov:skip=CKV2_AWS_61:Accepted risk — see docs/adr/0002-s3-security-scope.md
  #checkov:skip=CKV_AWS_145:Accepted risk — see docs/adr/0002-s3-security-scope.md
  bucket = "forensic-custody-evidence-logs-${data.aws_caller_identity.current.account_id}"

  object_lock_enabled = true
}

resource "aws_s3_bucket_public_access_block" "evidence_logs" {
  bucket = aws_s3_bucket.evidence_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "evidence_logs" {
  bucket = aws_s3_bucket.evidence_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "evidence_logs" {
  bucket = aws_s3_bucket.evidence_logs.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 1
    }
  }
}

resource "aws_s3_bucket_logging" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  target_bucket = aws_s3_bucket.evidence_logs.id
  target_prefix = "evidence-access-logs/"
}
