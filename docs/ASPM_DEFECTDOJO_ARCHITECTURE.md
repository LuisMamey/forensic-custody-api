# Centralized Vulnerability Management & ASPM Architecture (DefectDojo)

## 1. Problem Statement: Tool Sprawl & Fragmentation
The `forensic-custody-api` security pipeline runs multiple specialized scanners:
* **SAST:** Semgrep (`security.yml`)
* **SCA:** Govulncheck (`security.yml`) & Grype (`supply-chain.yml`)
* **Container Security:** Trivy (`security.yml`)
* **IaC Security:** Checkov (`security.yml`)
* **DAST:** OWASP ZAP (`security.yml`)
* **CSPM:** Prowler (`cspm.yml`)

Managing findings across siloed CI logs and separate reports leads to duplicate tracking, missed remediation deadlines, and lack of unified security metrics.

---

## 2. Ingestion & Deduplication Pipeline
**OWASP DefectDojo** acts as the centralized **Application Security Posture Management (ASPM)** engine.

### Automated Ingestion via CI/CD:
Pipelines export reports in standardized formats (SARIF, CycloneDX, JSON) and upload them to DefectDojo's REST API (`/api/v2/import-scan/`) using an API token:

```bash
curl -X POST "https://defectdojo.internal/api/v2/import-scan/" \
  -H "Authorization: Token $DOJO_API_KEY" \
  -F "scan_type=Trivy Scan" \
  -F "file=@trivy-results.json" \
  -F "engagement_name=CI Pipeline" \
  -F "product_name=forensic-custody-api" \
  -F "auto_create_context=true"
```

### Deduplication Engine:
When Trivy and Grype both flag the same CVE in the Debian base image, DefectDojo's hashing algorithm deduplicates the finding:
* Marks the primary finding as active.
* Links subsequent findings as duplicates to prevent inflated vulnerability counts.

---

## 3. SLA & Risk Acceptance Governance

### Corporate SLA Matrix:
| Severity | Target SLA | CI/CD Action |
|---|---|---|
| **Critical** | **48 Hours** | Blocker: Break CI pipeline on fixable CVEs. |
| **High** | **14 Days** | Alert: Notify team via Slack/Jira; block merge if fixable. |
| **Medium** | **30 Days** | Track: Backlog item for next sprint. |
| **Low / Info** | **90 Days** | Review: Remediate as capacity permits. |

### Formal Risk Acceptance:
Findings that cannot or should not be remediated immediately (e.g., S3 cross-region replication per ADR 0002) are transitioned in DefectDojo to **Risk Accepted**, requiring:
1. Architectural rationale (linking to corresponding ADR).
2. Approval by Security Lead.
3. Defined expiration date (forcing re-evaluation).
