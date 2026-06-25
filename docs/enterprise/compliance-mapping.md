# Compliance Mapping

How each gateway control supplies evidence for the frameworks an enterprise AI platform answers to. This is not legal advice — it's the control-to-obligation traceability an auditor or risk team expects, so the gateway becomes a *control implementation*, not just infrastructure.

Frameworks: **EU AI Act** (high-risk obligations), **NIST AI RMF 1.0** (Govern/Map/Measure/Manage), **ISO/IEC 42001** (AI management system), **ISO/IEC 27001** (infosec), **SOC 2** (Trust Services Criteria).

## Control → obligation matrix

| Gateway control | EU AI Act | NIST AI RMF | ISO 42001 | ISO 27001 | SOC 2 |
|---|---|---|---|---|---|
| **Token spend caps + pre-flight reject** | Art. 15 (robustness, resilience to overload) | MANAGE-2.1 (resourcing), MEASURE-2.6 | 8.3 operational control | A.8.6 capacity mgmt | CC7.x availability |
| **Cost attribution per team/agent** | Art. 12 (record-keeping) | GOVERN-1.x accountability | 9.1 monitoring | A.5.x accountability | CC2.x / CC3.x |
| **Content safety / Prompt Shields** | Art. 9 (risk mgmt), Art. 15 (accuracy/robustness) | MANAGE-2.2, MEASURE-2.7 (safety) | 6.1.2 AI risk treatment | A.8.x | CC6.x security |
| **Indirect-injection screening** | Art. 15 (resilience to manipulation) | MANAGE-4.x (incident), MEASURE-2.7 | 8.x operational | A.8.7 (malware-analogue) | CC6.x |
| **Egress containment (network isolation)** | Art. 15 (cybersecurity) | GOVERN-1.x, MANAGE-2.x | 8.x controls | A.8.20–8.23 network security | CC6.1 / CC6.6 |
| **Identity: Entra JWT + per-agent identity** | Art. 14 (human oversight via attributable actors) | GOVERN-2.x roles | 7.2 competence/roles | A.5.15–5.18 access control | CC6.1–6.3 |
| **Audit logs: prompts/completions/decisions** | Art. 12 + Art. 19 (logging, traceability) | MEASURE-1.x, MANAGE-4.x | 9.1 / 10.x | A.8.15 logging | CC4.x monitoring |
| **Data masking + retention + residency** | Art. 10 (data governance); GDPR overlap | MAP-4.x, MEASURE-2.10 (privacy) | 7.x / 8.x | A.8.10–8.12 | Privacy / Confidentiality TSC |
| **Workspaces: segregated admin + federated audit** | Art. 17 (quality mgmt system) | GOVERN-1.x, GOVERN-2.x | 5.x leadership, 6.x planning | A.5.2–5.4 segregation of duties | CC1.x / CC5.x |
| **CI/CD guardrails + change control + drift** | Art. 9 (lifecycle risk mgmt) | MANAGE-1.x, GOVERN-1.5 | 8.1 operational planning & control | A.8.32 change mgmt | CC8.1 change mgmt |
| **SecOps loop: Sentinel + Defender + alerts** | Art. 15 + Art. 9 (monitoring) | MEASURE-3.x, MANAGE-4.x | 9.1 / 10.2 | A.5.24–5.28 incident mgmt | CC7.2–7.4 |
| **Model failover / multi-region / AZ** | Art. 15 (resilience) | MANAGE-2.x | 8.x continuity | A.5.29–5.30 continuity | CC7.x / A1.x availability |
| **Maturity register (preview vs GA), caveats** | Art. 9 (documented risk), Art. 11 (technical documentation) | MAP-1.x, GOVERN-4.x | 7.5 documented information | A.5.37 documented procedures | CC2.2 |

## How to use this
1. **Map obligation → control → evidence.** For an audit, each row's "evidence" is concrete: Log Analytics queries, App Insights metrics, the git history of policy changes, the deployment `what-if` records, the Sentinel incidents. Policy-as-code in git *is* the Art. 11 / ISO 7.5 technical documentation.
2. **Profiles encode obligation tiers.** The `regulated` profile (see [capability-toggles.md](capability-toggles.md)) turns on every control a high-risk EU AI Act system needs; `prod` is a strong baseline; `dev` is non-production and labelled as such.
3. **Gaps are documented, not hidden.** [caveats.md](../caveats.md) is itself an Art. 9 / GOVERN-4 artifact: an honest risk register of what the controls do and don't do (streaming content-safety limits, cache staleness, preview surfaces). Auditors trust a documented limitation more than an undocumented assumption.
4. **The chokepoint centralizes evidence.** Because every model/tool/agent call transits one plane, "produce the log of every action agent X took in Q2" is one query — the difference between an audit you pass and one you can't answer.

## What the gateway does NOT cover (state these to risk teams)
- **In-model behavior** — bias, hallucination, training-data provenance — is governed at the model/Foundry layer, not the gateway. The gateway governs the *I/O boundary*.
- **Agent business logic** — whether an agent *should* take an action it's authorized to take is an app-layer decision; the gateway enforces *can it reach the system, at what rate, with what identity, on the record*.
- **Discovery of ungoverned paths** — the gateway can't govern a call that doesn't transit it. Network isolation (§4) plus periodic egress audits close this; it's a discipline, not an automatic guarantee.
