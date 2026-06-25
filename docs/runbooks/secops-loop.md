# Runbook — SecOps loop (Phase 3)

Telemetry is not governance; the closed loop is. This phase turns the token/prompt
logs the gateway already emits into **detection → alert → enforcement**. Flags:
`secOpsLoop` (the loop) and `dataMasking` (keep secrets out of the logs).

## What it deploys (`secOpsLoop` on)

| Resource | Purpose |
|---|---|
| Diagnostic setting on APIM → Log Analytics | Streams `GatewayLogs` + `GatewayLlmLogs`. The latter populates `ApiManagementGatewayLlmLog` (TotalTokens/PromptTokens/…) — the grounded source the budget alert queries. |
| Microsoft Sentinel onboarding | SIEM correlation on the workspace. |
| Action group `ag-aigov-secops` | Email receiver; the webhook receiver is where you wire the auto-throttle actuator. |
| Log alert `aigov-budget-threshold` | `sum(TotalTokens)` over 1h > `budgetTokensPerHour` → the auto-throttle trigger. |
| Log alert `aigov-injection-spike` | Count of 403 (content-safety blocks) on the governed API over 15m > `injection403Threshold` → likely attack wave. |
| Defender for APIs (subscription plan) | Threat protection on APIM. Deployed at sub scope in `main.bicep`. |

`dataMasking` (independent flag) Hides `api-key`/`subscription-key`/`Authorization` from
the App Insights diagnostic (`modules/llm-api.bicep`).

## The closed loop, end to end

```
agent → APIM → model
          │ TotalTokens, 403s → Log Analytics (GatewayLlmLogs / GatewayLogs)
          ▼
   budget-threshold alert ──► action group ──► [actuator] ──► az apim nv update
   (sum tokens > limit)         (email +          throttle.*    tokens-per-minute ↓
                                 webhook)                        (effective next request)
```

The alert detects; **`scripts/throttle.*` enforces** by lowering the `tokens-per-minute`
named value the governance policy reads — no redeploy, takes effect on the next requests.

### Wiring the actuator (pick one)

1. **Manual (simplest).** On the budget email, run:
   ```bash
   scripts/throttle.sh 100        # clamp to 100 TPM
   scripts/throttle.sh restore 1000
   ```
2. **Automation runbook (recommended for prod).** Create an Azure Automation account
   with a managed identity granted `API Management Service Contributor` on the APIM RG.
   Put the body of `throttle.sh`/`throttle.ps1` in a runbook, add a **webhook** receiver
   to the action group pointing at the runbook's webhook. Now a budget breach throttles
   automatically.
3. **Logic App.** Same idea with a Consumption Logic App (HTTP trigger from the action
   group → `az`/ARM call). Not deployed by this repo by design — see [caveats §12](../caveats.md#12-secops-auto-throttle-needs-an-actuator-you-wire).

> Throttling diverges live config from the repo; `scripts/drift-detect.*` will flag it
> until you redeploy or adopt the new cap. That's intended — the drift signal is your
> reminder to reconcile after an incident.

## Tuning the thresholds

```bash
az deployment sub create -l eastus2 -f infra/main.bicep \
  -p infra/main.parameters.json -p profile=prod \
  -p budgetTokensPerHour=20000000 -p injection403Threshold=50
```
Set `budgetTokensPerHour` to ~1.5× your expected peak hourly tokens so normal load
doesn't page anyone. Set `injection403Threshold` above your benign 403 floor (failed
auth, etc.) so only a genuine spike fires.

## Data protection: what `dataMasking` does and doesn't

- **Does:** Hides `api-key` + `subscription-key` + `Authorization` from telemetry — the
  secret-leak vector. Always turn this on when logging is on.
- **Does NOT:** redact PII inside prompt/completion **bodies** — APIM masking is
  headers/query only ([caveats §11](../caveats.md#11-data-masking-covers-headers-and-query-params--not-promptcompletion-bodies)).
- **Body PII control = `promptLogging`.** Leave LLM message-body logging **off** for
  sensitive BUs (the `regulated` profile defaults it off, keeping token *metadata* for
  cost/audit while dropping the message contents). For audit-with-redaction, add an
  ingestion-time DCR transform on the `ApiManagementGatewayLlmLog` table.

## Verify after deploy

- Portal → APIM → **Alerts** → confirm both rules present and enabled.
- Portal → **Microsoft Sentinel** → the workspace is listed (onboarded).
- Generate load, then in Log Analytics:
  ```kusto
  ApiManagementGatewayLlmLog | summarize sum(TotalTokens) by bin(TimeGenerated, 1h)
  ApiManagementGatewayLogs   | where ResponseCode == 403 | summarize count() by bin(TimeGenerated, 15m)
  ```
- Trip the budget alert in staging (low `budgetTokensPerHour`), confirm the email, then
  confirm `throttle.sh` lowers the cap and the next over-cap call returns 429.

## ⚠ Validate before production
- **Alert KQL tables/columns** (`ApiManagementGatewayLlmLog.TotalTokens`,
  `ApiManagementGatewayLogs.ResponseCode/ApiId`) are verified against the Azure Monitor
  table reference, but the LLM logging schema is evolving — confirm against your
  workspace before trusting the thresholds.
- **Defender for APIs** is a paid plan billed per subscription; enabling it via the
  `secOpsLoop` flag turns it on subscription-wide. Onboard individual APIM APIs from the
  Defender for Cloud **Recommendations** after the plan is on (≈40–50 min to appear).
