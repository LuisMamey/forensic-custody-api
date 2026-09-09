data "aws_iam_policy_document" "evidence_bucket_access" {
  statement {
    sid    = "ReadWriteEvidenceObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.evidence.arn}/*"]
  }

  statement {
    sid    = "ListEvidenceBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.evidence.arn]
  }
}

resource "aws_iam_policy" "evidence_bucket_access" {
  name   = "forensic-custody-evidence-access"
  policy = data.aws_iam_policy_document.evidence_bucket_access.json
}

resource "aws_iam_role" "evidence_api" {
  name = "forensic-custody-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "evidence_api" {
  role       = aws_iam_role.evidence_api.name
  policy_arn = aws_iam_policy.evidence_bucket_access.arn
}
