# Cost Attribution (`llm-emit-token-metric`)

GA control. See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it controls

This control answers "who spent what." It records usage figures — how many tokens (the
unit models bill by, roughly a word-piece) each request used — into App Insights (Azure's
app-monitoring service), tagged by team, product, and agent. Without it you would have a
hard spending cap (see [token-limits](./token-limits.md)) but no idea where the money went.

For a fleet of AI agents, this is what turns one undifferentiated bill into per-team
chargeback — billing each team for what it actually used — and lets you spot a runaway
agent before it trips the budget limit.

## The policy

From `infra/policies/llm-governance.xml` (inbound):

```xml
<llm-emit-token-metric namespace="ai-governance">
    <dimension name="Subscription" value="@(context.Subscription.Id)" />
    <dimension name="Product"      value="@(context.Product.Name)" />
    <dimension name="API"          value="@(context.Api.Name)" />
    <dimension name="Client IP"    value="@(context.Request.IpAddress)" />
    <dimension name="Agent ID"     value="@(context.Request.Headers.GetValueOrDefault('x-agent-id','unknown'))" />
</llm-emit-token-metric>
```

Namespace is `ai-governance`. Five custom dimensions — the Azure Monitor maximum (5
custom dimensions per policy).

## How it's wired in this repo

- Policy: `infra/policies/llm-governance.xml`.
- App Insights + Log Analytics provisioned in `infra/modules/monitoring.bicep`; the
  instrumentation/logger wiring is referenced from `infra/modules/apim.bicep`.
- `Agent ID` rides on the `x-agent-id` request header set by the calling agent.

## How to verify

1. Run `scripts/smoke-test.{sh,ps1}` to push a few completions through the gateway.
2. In App Insights → Metrics, select the `ai-governance` namespace and the token metric.
3. Split by the `Subscription` or `Agent ID` dimension — each team/agent shows its own
   token totals.
4. Confirm `team-research` and `team-platform` appear as distinct series.

## Caveats

- **Hard limit of 5 custom dimensions** per policy (Azure Monitor). Adding a sixth
  dimension means dropping one — don't exceed it or the metric silently breaks.
- Available on Developer and v2 tiers. **Not** on Consumption.
