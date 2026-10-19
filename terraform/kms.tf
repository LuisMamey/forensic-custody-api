# Dedicated AWS KMS Customer Managed Key (CMK) for Forensic Evidence Encryption
resource "aws_kms_key" "evidence" {
  description             = "Dedicated CMK for forensic custody evidence payload envelope encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_evidence_key_policy.json

  tags = {
    Environment = "Management"
    Project     = "forensic-custody-api"
    ManagedBy   = "Terraform"
  }
}

# KMS Key Alias for readable referencing
resource "aws_kms_alias" "evidence" {
  name          = "alias/forensic-custody-evidence-key"
  target_key_id = aws_kms_key.evidence.key_id
}

# Key Policy enforcing Least Privilege and Separation of Duties
data "aws_iam_policy_document" "kms_evidence_key_policy" {
  #checkov:skip=CKV_AWS_109:Accepted risk — see docs/adr/0007-kms-key-policy-architecture.md
  #checkov:skip=CKV_AWS_111:Accepted risk — see docs/adr/0007-kms-key-policy-architecture.md
  #checkov:skip=CKV_AWS_356:Accepted risk — see docs/adr/0007-kms-key-policy-architecture.md

  statement {
    sid    = "EnableRootIAMManagement"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEvidenceAPICryptoOperations"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.evidence_api.arn]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
  }
}
