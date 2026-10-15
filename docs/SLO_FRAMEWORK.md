# Forensic Custody API — SRE Service Level Objectives (SLO) & Error Budget Framework

## 1. Executive Summary & Philosophy
Following Google's Site Reliability Engineering (SRE) principles, reliability is the most fundamental feature of any system. In digital forensics and legal chain-of-custody, reliability is not merely an operational convenience—it is a legal prerequisite for court admissibility.

100% availability is explicitly rejected as an anti-pattern. Instead, this framework codifies an objective mathematical contract balancing innovation velocity with strict forensic availability and latency constraints.

---

## 2. Core SRE Definitions

* **Service Level Indicator (SLI):** A carefully defined quantitative measure of some aspect of the level of service that is provided (e.g., proportion of valid HTTP requests that return non-5xx status).
* **Service Level Objective (SLO):** A target value or range of values for a service level that is measured by an SLI (e.g., SLI $\ge$ 99.9% over a 30-day rolling window).
* **Error Budget:** The allowable fraction of unreliability over the measurement window:
  $$\text{Error Budget} = 100\% - \text{SLO} = 100\% - 99.9\% = 0.1\%$$
* **Burn Rate:** The rate at which the service consumes its error budget relative to the SLO window. A burn rate of 1.0 consumes exactly 100% of the budget over 30 days.

---

## 3. Concrete Numerical Targets & Specifications

### SLO 1: Forensic API Availability (Golden Signal: Errors)
* **Objective:** **99.9%** of all valid HTTP requests return a non-5xx status code over a **30-day rolling window**.
* **Allowed Downtime / Failure Budget:** 43.2 minutes per 30-day period.
* **SLI Specification:**
  $$\text{SLI}_{\text{availability}} = \frac{\sum \text{Successful Requests (HTTP status} < 500)}{\sum \text{Total Requests Validated}}$$
* **PromQL Calculation:**
  ```promql
  sum(rate(forensic_http_requests_total{status!~"5.."}[5m]))
  /
  sum(rate(forensic_http_requests_total[5m]))
  ```

### SLO 2: Evidence Read Latency (Golden Signal: Latency)
* **Objective:** The **99th percentile (p99)** response time for evidence metadata and case retrieval operations (`GET` requests) must be **less than 250 milliseconds** measured over a 30-day window.
* **Target Audience:** Forensic auditors and investigative personnel conducting real-time case validation.
* **SLI Specification:** Proportion of GET operations completed in $\le 250\text{ ms}$.
* **PromQL Calculation:**
  ```promql
  histogram_quantile(0.99, sum(rate(forensic_http_request_duration_seconds_bucket{method="GET"}[5m])) by (le))
  ```

---

## 4. Error Budget Policy & Enforcement Actions

| Error Budget Remaining | Status | Automated Policy & Engineering Action |
|---|---|---|
| **$100\% - 50\%$** | Healthy | Normal operations. Full deployment velocity permitted. |
| **$50\% - 20\%$** | Warning | Heightened awareness. Postmortems required for any Sev-2 incident. Non-urgent releases proceed with care. |
| **$< 20\%$** | Critical | Feature Freeze. Code deployments restricted to reliability fixes, security patches, and performance optimizations. |
| **$0\%$ (Exhausted)** | Breached | Full deployment block (except emergency rollback / hotfix). Engineering priorities pivot 100% to reliability debt. |

---

## 5. Multi-Window Multi-Burn-Rate Alerting Strategy

To eliminate alert fatigue while preventing undetected budget exhaustion, alerts are configured using multi-window burn-rate analysis:

* **Page Alert (Urgent Sev-1):** 14.4x burn rate over 1 hour (consumes 2% of budget in 1 hour) AND 14.4x over 5 minutes.
* **Ticket Alert (Sev-2):** 6x burn rate over 6 hours (consumes 5% of budget in 6 hours) AND 6x over 30 minutes.