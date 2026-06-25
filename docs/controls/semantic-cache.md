# Semantic Cache (`llm-semantic-cache-lookup` / `-store`)

GA control. See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it controls

Returns a cached completion when an incoming prompt is *semantically similar* to a prior
one — not just byte-identical. Agents re-ask near-duplicate questions constantly; serving
those from cache cuts token spend and latency. Lookup runs inbound; store runs outbound.

## The policy

From `infra/policies/llm-governance.xml`:

```xml
<!-- inbound, LAST in order (after content-safety) -->
<llm-semantic-cache-lookup
    score-threshold="{{cache-score-threshold}}"
    embeddings-backend-id="embeddings-backend"
    embeddings-backend-auth="system-assigned">
    <vary-by>@(context.Subscription.Id)</vary-by>
</llm-semantic-cache-lookup>
```

```xml
<!-- outbound -->
<llm-semantic-cache-store duration="3600" />
```

`score-threshold`: **lower = stricter** match. Start tight — default `0.05`.
`vary-by` subscription so teams cannot read each other's cached answers.

## How it's wired in this repo

- Policy: `infra/policies/llm-governance.xml`.
- Azure Managed Redis (with the **RediSearch** module) provisioned in
  `infra/modules/redis.bicep` and registered as the APIM external cache.
- `text-embedding-3-small` deployment (`embeddings`) on the Azure OpenAI account
  (`infra/modules/openai.bicep`), surfaced as the `embeddings-backend` whose MI auth is
  the `embeddings-backend-auth="system-assigned"` attribute.
- `cache-score-threshold` is a named value — tune via
  [runbooks/tune-cache](../runbooks/tune-cache.md).

## How to verify

1. Run `scripts/smoke-test.{sh,ps1}` twice with the *same* prompt; the second response
   should be served from cache (much lower latency, no backend token burn).
2. Send a *reworded but equivalent* prompt — still a hit at the default threshold.
3. Confirm a different team key does **not** hit the first team's cache (vary-by).
4. Cache hit rate is visible via APIM trace / App Insights.

## Caveats

- **RediSearch can only be enabled at cache CREATION** — it cannot be retrofitted. A
  Redis instance built without it must be replaced, not upgraded.
- Similarity matching can surface **stale, incorrect, or unsafe** answers. That is why
  `llm-content-safety` runs **before** the cache lookup — safety screens first, cache
  serves second. Do not reorder.
- Available on Developer and v2 tiers. **Not** on Consumption.
