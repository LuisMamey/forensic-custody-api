# ADR 0008: AWS Secrets Manager rotation scope for application signing keys

## Status
Accepted

## Context
Checkov policy `CKV2_AWS_57` flags the AWS Secrets Manager resource (`aws_secretsmanager_secret.api_secrets` in `terraform/secrets.tf`):
- `CKV2_AWS_57`: "Ensure Secrets Manager secrets should have automatic rotation enabled".

## Decision
We deliberately accept suppressing automated rotation for the `forensic-custody/api/jwt-secret` resource in this stage for the following reasons:

- **Application-Layer Key Architecture:** Automated rotation in AWS Secrets Manager requires provisioning and maintaining a dedicated AWS Lambda function. While turnkey Lambda templates exist for relational databases (RDS, PostgreSQL, MySQL), application-level symmetric cryptographic signing keys (like our HMAC-SHA256 JWT key) require dual-key verification grace periods to avoid instantly invalidating all active client authentication sessions.
- **Operator-Driven Synchronization (ESO):** The secret is consumed into Kubernetes via **External Secrets Operator (ESO)**. ESO continuously polls Secrets Manager (`refreshInterval`). When a new secret version is published by the security officer, ESO synchronizes the update into the Kubernetes native secret without requiring a custom rotation Lambda function.
- **Cost & Scope Optimization:** Deploying and maintaining a standalone rotation Lambda, VPC endpoints, and invocation IAM roles adds infrastructure overhead without increasing security for static JWT verification keys in this single-tenant deployment baseline.

## Consequences
- **Positive:** Avoids complex dual-verification Lambda rotators; relies on ESO native polling synchronization for zero-trust key updates.
- **Negative / Accepted Risk:** Secrets are rotated through scheduled operator deployments or administrative updates rather than automatic Lambda triggers.
- **Suppression:** Suppressed via `#checkov:skip=CKV2_AWS_57:Accepted risk — see docs/adr/0008-secrets-manager-rotation-scope.md` in `terraform/secrets.tf`.
