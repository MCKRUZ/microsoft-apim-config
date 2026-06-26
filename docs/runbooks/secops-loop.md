# Runbook — SecOps loop (Phase 3)

Telemetry is not governance; the closed loop is. This phase turns the token/prompt
logs the gateway already emits into **detection → alert → enforcement**. Flags:
`secOpsLoop` (the loop) and `dataMasking` (keep secrets out of the logs).

## What it deploys (`secOpsLoop` on)

| Resource | Purpose |
|---|---|
| Diagnostic setting on APIM → Log Analytics | Streams `GatewayLogs` + `GatewayLlmLogs`. The second one fills the `ApiManagementGatewayLlmLog` table (TotalTokens/PromptTokens/…) — the trustworthy source the budget alert reads. |
| Microsoft Sentinel onboarding | Connects the logs to a security-monitoring system that correlates events to spot attacks (a "SIEM"). |
| Action group `ag-aigov-secops` | The target an alert notifies or triggers. It has an email receiver, plus a webhook receiver where you connect the automatic throttling action. |
| Log alert `aigov-budget-threshold` | Fires when `sum(TotalTokens)` over 1 hour exceeds `budgetTokensPerHour` — the trigger for automatic throttling. |
| Log alert `aigov-injection-spike` | Fires when the number of 403 responses (content-safety blocks) on the governed API over 15 minutes exceeds `injection403Threshold` — a likely attack wave. |
| Defender for APIs (subscription plan) | Threat protection for the gateway. Turned on across the whole subscription in `main.bicep`. |

`dataMasking` (a separate flag) hides `api-key`/`subscription-key`/`Authorization` from
the App Insights logs (`modules/llm-api.bicep`), so credentials never land in telemetry.

## The closed loop, end to end

```
agent → APIM → model
          │ TotalTokens, 403s → Log Analytics (GatewayLlmLogs / GatewayLogs)
          ▼
   budget-threshold alert ──► action group ──► [actuator] ──► az apim nv update
   (sum tokens > limit)         (email +          throttle.*    tokens-per-minute ↓
                                 webhook)                        (effective next request)
```

The alert spots the problem; **`scripts/throttle.*` acts on it** by lowering the `tokens-per-minute`
value the governance policy reads. No redeploy is needed, and it takes effect on the next requests.

### Wiring the actuator (pick one)

The "actuator" is whatever automatically runs the throttle when the alert fires. Pick one:

1. **Manual (simplest).** When the budget email arrives, run:
   ```bash
   scripts/throttle.sh 100        # clamp to 100 TPM
   scripts/throttle.sh restore 1000
   ```
2. **Automation runbook (recommended for production).** Create an Azure Automation account
   with an Azure-issued identity (no stored password) granted `API Management Service Contributor` on the gateway's resource group.
   Put the contents of `throttle.sh`/`throttle.ps1` into a runbook, then add a **webhook** receiver
   to the alert target (action group) that points at the runbook's webhook. Now a budget breach throttles
   automatically.
3. **Logic App.** The same idea using a Consumption Logic App (an HTTP trigger from the alert
   target makes the `az`/ARM call). This repo deliberately doesn't deploy it — see [caveats §12](../caveats.md#12-auto-throttling-on-overspend-needs-one-wiring-step).

> Throttling makes the live configuration differ from the repo, so the dry-run check (`scripts/drift-detect.*`) will flag it
> until you either redeploy or adopt the new cap. That's intentional — the drift signal is your
> reminder to reconcile things once the incident is over.

## Tuning the thresholds

```bash
az deployment sub create -l eastus2 -f infra/main.bicep \
  -p infra/main.parameters.json -p profile=prod \
  -p budgetTokensPerHour=20000000 -p injection403Threshold=50
```
Set `budgetTokensPerHour` to about 1.5 times your expected peak hourly tokens, so normal load
doesn't wake anyone up. Set `injection403Threshold` above your normal baseline of harmless 403s (failed
sign-ins, etc.), so only a genuine spike triggers the alert.

## Data protection: what `dataMasking` does and doesn't

- **Does:** hide `api-key` + `subscription-key` + `Authorization` from the logs — the most likely way a
  secret leaks. Always turn this on whenever logging is on.
- **Does NOT:** remove personal data (PII) inside the prompt/completion **message bodies** — the gateway's masking covers
  headers and query parameters only ([caveats §11](../caveats.md#11-data-masking-covers-headers-and-query-params--not-promptcompletion-bodies)).
- **Message-body PII is controlled by `promptLogging`.** Keep message-body logging **off** for
  sensitive business units (the `regulated` profile turns it off by default, keeping token *counts* for
  cost and audit while dropping the actual message contents). If you need to log bodies but with sensitive fields removed, add a
  rule that strips or transforms fields as the logs are collected (a Data Collection Rule, "DCR") on the `ApiManagementGatewayLlmLog` table.

## Verify after deploy

- Portal → APIM → **Alerts** → confirm both rules present and enabled.
- Portal → **Microsoft Sentinel** → the workspace is listed (onboarded).
- Generate load, then in Log Analytics:
  ```kusto
  ApiManagementGatewayLlmLog | summarize sum(TotalTokens) by bin(TimeGenerated, 1h)
  ApiManagementGatewayLogs   | where ResponseCode == 403 | summarize count() by bin(TimeGenerated, 15m)
  ```
- Deliberately trip the budget alert in staging (set a low `budgetTokensPerHour`), confirm the email arrives, then
  confirm `throttle.sh` lowers the cap and the next call over the cap returns 429.

## ⚠ Validate before production
- The **log queries behind the alerts** (the KQL using `ApiManagementGatewayLlmLog.TotalTokens`,
  `ApiManagementGatewayLogs.ResponseCode/ApiId`) are checked against the Azure Monitor
  table reference, but the LLM logging schema is still changing — confirm the table and column names against your own
  workspace before you rely on the thresholds.
- **Defender for APIs** is a paid plan billed per subscription, and turning it on with the
  `secOpsLoop` flag enables it across the whole subscription. Once the plan is on, add individual gateway APIs from the
  Defender for Cloud **Recommendations** (they take roughly 40–50 minutes to appear).
