# Compliance Mapping

How each control in the gateway produces the evidence demanded by the rulebooks an enterprise AI platform has to answer to. This is not legal advice. It is the trail an auditor or risk team expects — showing, for each obligation, which control satisfies it — so the gateway counts as an actual implementation of those controls, not just plumbing.

The rulebooks covered here: the **EU AI Act** (Europe's law on high-risk AI), **NIST AI RMF 1.0** (a US government AI risk framework organised as Govern / Map / Measure / Manage), **ISO/IEC 42001** (the international standard for running an AI management system), **ISO/IEC 27001** (the international standard for information security), and **SOC 2** (a US audit standard built on its "Trust Services Criteria").

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
1. **Trace each obligation to a control, and the control to its evidence.** For an audit, the evidence in each row is concrete: log queries, performance metrics, the version-control history of every policy change, the records of what each deployment previewed it would change, and the security incidents the monitoring system raised. Keeping policy as code in version control *is* the technical documentation the EU AI Act (Art. 11) and ISO (7.5) require.
2. **The environment profiles map to obligation levels.** The `regulated` profile (see [capability-toggles.md](capability-toggles.md)) turns on every control a high-risk EU AI Act system needs; `prod` is a strong baseline; `dev` is non-production and clearly labelled as such.
3. **Gaps are written down, not hidden.** [caveats.md](../caveats.md) is itself a required risk-documentation artifact (EU AI Act Art. 9 / NIST GOVERN-4): an honest register of what the controls do and don't do — content-safety limits on streaming responses, the chance of a stale cached answer, the preview features. Auditors trust a written-down limitation more than an unstated assumption.
4. **One chokepoint puts all the evidence in one place.** Because every model, tool, and agent call goes through one layer, answering "show me the log of every action agent X took in Q2" is a single query — the difference between an audit you pass and one you simply can't answer.

## What the gateway does NOT cover (state these to risk teams)
- **How the model itself behaves** — bias, made-up answers, where its training data came from — is handled at the model layer, not the gateway. The gateway governs what crosses its boundary in and out, not what happens inside the model.
- **An agent's business logic** — whether an agent *should* take an action it is allowed to take is a decision for the application, not the gateway. The gateway only enforces whether it *can* reach the system, how often, with which identity, and on the record.
- **Finding paths that bypass the gateway** — the gateway can't govern a call that never goes through it. Network isolation (§4) plus periodic checks of what is leaving the network close this gap, but it takes ongoing discipline; it is not automatic.
