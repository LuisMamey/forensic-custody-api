# Restrict to same-account, same-bucket log delivery to avoid cross-account
# log injection from unrelated buckets.
data "aws_iam_policy_document" "evidence_logs" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.evidence_logs.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.evidence.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "evidence_logs" {
  bucket = aws_s3_bucket.evidence_logs.id
  policy = data.aws_iam_policy_document.evidence_logs.json
}
