# Token Limits (`llm-token-limit`)

GA control. See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it controls

Per-minute token rate (TPM) plus a token quota over a longer period, keyed to the
subscription = team identity. Agents are bursty and can run away — a single bad loop
can burn a month of budget in minutes. This is the hard spend cap that makes an agent
fleet financially safe. `estimate-prompt-tokens` rejects oversize prompts pre-flight,
so a rejected request never bills the backend.

## The policy

From `infra/policies/llm-governance.xml` (inbound, after auth):

```xml
<llm-token-limit
    counter-key="@(context.Subscription.Id)"
    tokens-per-minute="{{tpm-limit}}"
    token-quota="{{token-quota}}"
    token-quota-period="Monthly"
    estimate-prompt-tokens="true"
    remaining-tokens-header-name="x-tokens-remaining"
    tokens-consumed-header-name="x-tokens-consumed" />
```

- `429` returned when the per-minute rate is exceeded.
- `403` returned when the period quota is exhausted.

## How it's wired in this repo

- Policy: `infra/policies/llm-governance.xml`.
- Named values `tpm-limit`, `token-quota` provisioned in `infra/modules/apim.bicep`.
- `counter-key` is `context.Subscription.Id` — each team product/subscription
  (`team-research`, `team-platform`) is an independent counter.

## How to verify

1. Run `scripts/smoke-test.{sh,ps1}` against
   `/openai/deployments/chat/chat/completions?api-version=2024-10-21` with a team key
   in the `api-key` header.
2. Inspect `x-tokens-remaining` / `x-tokens-consumed` response headers — they decrement.
3. Fire requests fast enough to exceed TPM → expect `429`.
4. Send a deliberately huge prompt → expect pre-flight rejection (no backend bill).

## Caveats

- **Per-region counting.** Token quota counts PER gateway region/instance. A
  company-wide cap needs per-region math. Note: the older *request*-based limits summed
  across regions; this token limit does **not**. Multi-region (PremiumV2) changes the
  budget arithmetic.
- Available on Developer and v2 tiers. **Not** on Consumption.
