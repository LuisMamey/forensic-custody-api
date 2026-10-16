# Incident Postmortem: INCIDENT-2026-001 — Load Test Failure Due to Malformed JWT and Secret Leak Prevention

## 1. Executive Summary
* **Date of Incident:** 2026-10-16
* **Incident Commander / Facilitator:** Lead Platform & SRE Engineer
* **Participants:** DevSecOps Team, Platform Engineering
* **Severity Level:** Sev-2 (Major — Automated Quality Gate & Load Test Degradation)
* **Status:** Action Items Complete

---

## 2. Impact & SLO Consumption
* **Duration of Outage / Degradation:** ~15 minutes during local pre-merge load testing.
* **User Impact:** Zero production customer impact (caught prior to production deployment in staging/local verification).
* **SLO Impact:**
  - **Availability SLO Breached?** Yes, within the isolated k6 load test runner (`http_req_failed: 33.3%` due to HTTP 401 responses).
  - **Error Budget Consumed:** 0% of production budget; 100% of synthetic test budget.
  - **Latency SLO Breached?** No (p99 latency remained < 10ms throughout execution).

---

## 3. Incident Timeline (UTC)
* `20:45` — **Trigger:** Initial k6 load test executed against the API with a mock plain-text authorization string (`forensic-custody-enterprise-secret-key-32b:INVESTIGATOR`).
* `20:48` — **Detection:** k6 runner aborted with error: `thresholds on metrics 'checks, http_req_failed' have been crossed`. API returned HTTP 401 Unauthorized for all `/cases` requests.
* `20:49` — **Triage:** Engineers analyzed server logs and confirmed RBAC middleware (`internal/auth/roles.go`) properly rejected non-cryptographic tokens.
* `20:53` — **Secondary Trigger (Secret Prevention):** A valid HMAC-SHA256 test JWT was embedded in `tests/load/k6-slo-test.js`. Local `pre-commit` hook (Gitleaks) intercepted the commit and rejected it due to high-entropy JWT pattern matching (`RuleID: jwt`).
* `20:57` — **Mitigation & Resolution:** Refactored `k6-slo-test.js` to decouple credentials using `__ENV.AUTH_TOKEN` dynamic environment injection. Configured CI workflow to synthesize ephemeral test tokens in-memory without persisting them in git history. Load test re-executed with 100% pass rate across 8,070 requests.

---

## 4. Root Cause Analysis (The 5 Whys Methodology)
1. **Why did the initial k6 load test fail?**
   - The `/cases` endpoint rejected all requests with HTTP 401 Unauthorized.
2. **Why were requests rejected with 401?**
   - The HTTP request header contained a raw mock string instead of a valid three-part Base64URL-encoded JSON Web Token.
3. **Why did the mock string fail?**
   - The Go backend strictly verifies the cryptographic HMAC-SHA256 signature and JSON claims structure via `TokenService.VerifyToken()`.
4. **Why did the subsequent fix trigger a git commit failure?**
   - Embedding a real signed JWT in the source file triggered Gitleaks' deterministic entropy analysis rule for JWTs.
5. **Why was a static token placed in code? (Root Cause)**
   - The test script lacked an abstraction for external environment variable injection (`__ENV.AUTH_TOKEN`), conflating test logic with credential provisioning.

---

## 5. What Went Well / What Went Poorly
### What Went Well:
* **Defense-in-depth validated:** The Go backend's RBAC middleware successfully blocked invalid tokens even under high concurrency (322 req/s).
* **Supply chain security worked:** Gitleaks pre-commit hooks prevented persistent credential exposure before code ever reached GitHub.
* **Rapid recovery:** The architecture was refactored in under 10 minutes to support standard cloud-native environment variable injection.

### What Went Poorly:
* Initial load test script was authored with synthetic credentials without verifying Go auth middleware contract first.

---

## 6. Corrective Actions & Action Items (Blameless Engineering)

| Action Item | Type | Owner | Ticket / PR | Priority | Status |
|---|---|---|---|---|---|
| Decouple k6 credentials via `__ENV.AUTH_TOKEN` | Preventative | SRE Team | PR #28 | High | Done |
| Synthesize ephemeral JWTs in CI memory | Preventative | DevSecOps | PR #28 | High | Done |
| Document SRE Postmortem standard in `docs/postmortems/` | Process | SRE Team | PR #29 | Medium | Done |
