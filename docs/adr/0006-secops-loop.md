# ADR-0006 — SecOps loop: detection deployed, enforcement actuated

**Status:** Accepted · **Date:** 2026-06-25

## Context
Phase 3 of the [target architecture](../enterprise/target-architecture.md) (§9, `secOpsLoop`)
turns monitoring data into action — this is the security-operations loop. It adds Microsoft's
threat-monitoring tools (Sentinel and Defender), automatic slowdown when a budget is blown,
alerting when there's a spike of prompt-injection attempts (malicious inputs trying to hijack the
model), and protection of sensitive data in the logs. The real question: how much of the "action"
half can honestly ship as production-ready Bicep templates, versus a step you wire up by hand and
document.

## Decision
- **Ship the detection side as production-ready Bicep** (`modules/secops.bicep`): send the gateway
  logs (`GatewayLogs` + `GatewayLlmLogs`) to Log Analytics, onboard Sentinel, set up an alert
  recipient group, and create two alerts (budget threshold breached, and a spike of rejected
  requests that signals injection attempts). Defender for APIs is turned on at the subscription
  level in `main.bicep`.
- **Base every alert on a real, verified data table.** The budget alert sums token usage
  (`sum(TotalTokens)`) from `ApiManagementGatewayLlmLog`; the injection alert counts "403"
  rejections from `ApiManagementGatewayLogs`. Both tables and columns were checked against the
  official Azure Monitor reference.
- **Take the action with a script, not a pre-built workflow.** When the budget alert fires, the fix
  (lowering the per-minute usage cap) is `scripts/throttle.*`, connected to the alert group through
  an Automation runbook / Logic App. Hand-coding that workflow into Bicep is fragile for a reference
  repo; the script plus documented wiring is more durable.
- **`dataMasking` does only what it can.** It hides the `api-key`/`subscription-key`/
  `Authorization` secrets so they can't leak into the App Insights logs. It does **not** scrub the
  actual prompt or answer text — masking in the API gateway (Azure API Management, "APIM") only
  covers headers and query strings.

## Rationale
- The alternative (faking the auto-slowdown as a Logic App, or alerting on a metric name we hadn't
  verified) would misrepresent what actually works. Detection is genuinely production-ready;
  taking action genuinely needs something to pull the trigger. Saying so plainly is the golden-copy
  contract.
- Token *counts* (`TotalTokens`) are just usage numbers — safe to collect even in the strictest
  `regulated` profile. The prompt and answer *text* is the personal-data (PII) risk, and that's
  controlled by `promptLogging`, not by masking. Keeping the two separate avoids the trap of
  claiming "we masked it" when nothing masked the actual text.

## Consequences
- Out of the box: Sentinel + Defender + two alerts + email + one-command throttle. Fully
  automatic throttle is a documented runbook/Logic App wiring step.
- `dataMasking` flag wires header/query Hide into `modules/llm-api.bicep` (per-direction
  `frontend`/`backend` pipeline settings — masking is not a top-level diagnostic property).
- New caveats [§11](../caveats.md) (masking scope) and [§12](../caveats.md) (actuator + Defender billing).
- Compiles clean; `dev` (secOpsLoop off) is unchanged. `prod`/`regulated` get the loop.
