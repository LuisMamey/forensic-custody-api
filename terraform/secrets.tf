# AWS Secrets Manager Secret for Forensic API sensitive configuration
resource "aws_secretsmanager_secret" "api_secrets" {
  #checkov:skip=CKV2_AWS_57:Accepted risk — see docs/adr/0008-secrets-manager-rotation-scope.md
  name                    = "forensic-custody/api/jwt-secret"
  description             = "JWT signing secret and sensitive credentials for forensic custody API"
  kms_key_id              = aws_kms_key.evidence.arn
  recovery_window_in_days = 0 # Immediate deletion for development lab

  tags = {
    Environment = "production"
    Project     = "forensic-custody-api"
    ManagedBy   = "terraform"
  }
}

# IAM Policy allowing External Secrets Operator to read the specific secret
data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid    = "AllowReadForensicApiSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.api_secrets.arn]
  }

  statement {
    sid    = "AllowKmsDecryptForSecret"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = [aws_kms_key.evidence.arn]
  }
}

resource "aws_iam_policy" "external_secrets" {
  name        = "forensic-custody-eso-secrets-policy"
  description = "Allows External Secrets Operator to retrieve forensic API secrets"
  policy      = data.aws_iam_policy_document.external_secrets.json

  tags = {
    Environment = "production"
    Project     = "forensic-custody-api"
  }
}

# IAM Role assumed by External Secrets Operator via EKS Pod Identity
data "aws_iam_policy_document" "eso_pod_identity_trust" {
  statement {
    sid     = "AllowEksPodIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "forensic-custody-api-eso-role"
  description        = "IAM role for External Secrets Operator pod identity"
  assume_role_policy = data.aws_iam_policy_document.eso_pod_identity_trust.json

  tags = {
    Environment = "production"
    Project     = "forensic-custody-api"
  }
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

# EKS Pod Identity Association linking Kubernetes ServiceAccount to IAM Role
resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets-sa"
  role_arn        = aws_iam_role.external_secrets.arn
}
