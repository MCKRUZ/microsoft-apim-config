# ADR-0006 — SecOps loop: detection deployed, enforcement actuated

**Status:** Accepted · **Date:** 2026-06-25

## Context
Phase 3 of the [target architecture](../enterprise/target-architecture.md) (§9, `secOpsLoop`)
turns telemetry into action: Sentinel/Defender for threat coverage, budget-breach →
auto-throttle, injection-spike alerting, and log data protection. The question was how
much of the "action" is honestly deployable as GA Bicep vs. a documented wiring step.

## Decision
- **Deploy the detection plane as GA Bicep** (`modules/secops.bicep`): a diagnostic
  setting routing `GatewayLogs` + `GatewayLlmLogs` to Log Analytics, Sentinel onboarding,
  an action group, and two log alerts (budget threshold, injection 403-spike). Defender
  for APIs is a subscription-scope plan, enabled in `main.bicep`.
- **Ground every alert query in a verified table.** Budget = `sum(TotalTokens)` from
  `ApiManagementGatewayLlmLog`; injection = 403 count from `ApiManagementGatewayLogs`.
  Both tables/columns verified against the Azure Monitor table reference.
- **Actuate enforcement with a script, not a deployed workflow.** The budget alert's
  remediation (lower the `tokens-per-minute` named value) is `scripts/throttle.*`, wired
  to the action group via an Automation runbook / Logic App. A hand-rolled workflow JSON
  in Bicep is brittle for a reference repo; the script + documented wiring is more durable.
- **`dataMasking` does only what it can.** It Hides the `api-key`/`subscription-key`/
  `Authorization` secret-leak vector on the App Insights diagnostic. It does **not** touch
  prompt/completion bodies — APIM masking is headers/query only.

## Rationale
- The alternative (faking auto-throttle as a Logic App, or alerting on an unverified
  custom-metric name) would be dishonest about what reliably works. Detection is genuinely
  GA; remediation genuinely needs an actuator. Saying so is the golden-copy contract.
- Token *counts* (`TotalTokens`) are metadata, safe to collect even in `regulated`. Prompt
  *bodies* are the PII risk and are governed by `promptLogging`, not masking — keeping the
  two concerns separate avoids the trap of "we masked it" when nothing masked the body.

## Consequences
- Out of the box: Sentinel + Defender + two alerts + email + one-command throttle. Fully
  automatic throttle is a documented runbook/Logic App wiring step.
- `dataMasking` flag wires header/query Hide into `modules/llm-api.bicep` (per-direction
  `frontend`/`backend` pipeline settings — masking is not a top-level diagnostic property).
- New caveats [§11](../caveats.md) (masking scope) and [§12](../caveats.md) (actuator + Defender billing).
- Compiles clean; `dev` (secOpsLoop off) is unchanged. `prod`/`regulated` get the loop.
