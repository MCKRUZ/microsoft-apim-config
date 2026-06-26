# Token Limits (`llm-token-limit`)

GA control. See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it controls

This is the hard spending limit that makes a fleet of AI agents financially safe. Agents
are unpredictable and can run away — a single bad loop can burn a month of budget in
minutes. This control caps that.

It works on two clocks, both tied to each team's identity (their subscription). First, a
speed limit measured in tokens per minute (a token is the unit the model bills by, roughly
a word-piece) — "TPM" for short. Second, a total budget (quota) over a longer period, such
as a month. Because `estimate-prompt-tokens` checks the size of a request before it is sent
("pre-flight"), an oversized request is rejected up front and never costs anything at the
model backend.

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
