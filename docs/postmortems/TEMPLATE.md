# Incident Postmortem: [INCIDENT-YYYY-NNN] — [Brief Incident Title]

## 1. Executive Summary
* **Date of Incident:** YYYY-MM-DD
* **Incident Commander / Facilitator:** [Name / Role]
* **Participants:** [Team Members Involved]
* **Severity Level:** [Sev-1 (Critical) | Sev-2 (Major) | Sev-3 (Minor)]
* **Status:** [Draft | Under Review | Action Items Complete]

---

## 2. Impact & SLO Consumption
* **Duration of Outage / Degradation:** [X minutes / hours]
* **User Impact:** [Number of users, requests, or forensic operations affected]
* **SLO Impact:**
  - **Availability SLO Breached?** [Yes / No] (Monthly Target: 99.9%)
  - **Error Budget Consumed:** [X.XX%] of total monthly failure budget.
  - **Latency SLO Breached?** [Yes / No] (p99 < 250ms target)

---

## 3. Incident Timeline (UTC)
* `HH:MM` — **Trigger:** The change or event that introduced the anomaly occurs.
* `HH:MM` — **Alert / Detection:** Alertmanager triggers alert (`[AlertName]`) to Slack/PagerDuty.
* `HH:MM` — **Triage:** Engineers acknowledge incident and begin investigation.
* `HH:MM` — **Mitigation:** Hotfix deployed, rollback initiated, or traffic rerouted.
* `HH:MM` — **Resolution:** System metrics return to healthy baseline; error budget burn rate drops to zero.

---

## 4. Root Cause Analysis (The 5 Whys Methodology)
* **1. Why did the service fail?**
  - [Answer]
* **2. Why did that condition occur?**
  - [Answer]
* **3. Why wasn't that prevented by automated controls?**
  - [Answer]
* **4. Why wasn't it caught during testing or CI/CD?**
  - [Answer]
* **5. Why did the underlying process or architecture allow this? (Root Cause)**
  - [Root Cause Summary]

---

## 5. What Went Well / What Went Poorly
### What Went Well:
* [e.g., Alerting fired within 2 minutes of error budget burn rate increase.]
* [e.g., Graceful shutdown prevented in-flight evidence corruption.]

### What Went Poorly:
* [e.g., Runbooks lacked clear troubleshooting steps for token expiration.]
* [e.g., Dashboard took 10 minutes to locate appropriate logs.]

---

## 6. Corrective Actions & Action Items (Blameless Engineering)

| Action Item | Type | Owner | Ticket / PR | Priority |
|---|---|---|---|---|
| [Implement automated pre-deployment token validation] | Preventative | [Owner] | [#123] | High |
| [Add Falco rule for unauthorized token manipulation] | Detective | [Owner] | [#124] | Medium |
| [Update Alertmanager runbook documentation] | Process | [Owner] | [#125] | Low |
