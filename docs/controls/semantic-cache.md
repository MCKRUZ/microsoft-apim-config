# Semantic Cache (`llm-semantic-cache-lookup` / `-store`)

GA control. See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it controls

This control saves money and time by reusing past answers. When a new request means roughly
the same thing as one already answered, it returns the saved reply instead of paying the
model again. The key word is *meaning*: it matches on meaning, not exact wording, so a
reworded version of an earlier question still counts as a match. AI agents ask near-duplicate
questions constantly, so serving those from this saved store ("cache") cuts both token spend
(tokens are the unit models bill by) and the wait for a reply (latency). The check happens on
the way in; saving a fresh answer happens on the way out.

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

`score-threshold` sets how close a match has to be: **lower = stricter**. Start tight —
default `0.05` — and loosen carefully. `vary-by` keys the saved answers to each team's
subscription, so teams cannot read each other's cached replies.

## How it's wired in this repo

- Policy: `infra/policies/llm-governance.xml`.
- Azure Managed Redis — the cache store — with **RediSearch** (the search feature that
  compares meaning) turned on, provisioned in `infra/modules/redis.bicep` and registered as
  the external cache for the API gateway (Azure API Management, "APIM").
- `text-embedding-3-small` deployment (`embeddings`) on the Azure OpenAI account
  (`infra/modules/openai.bicep`) — this is what converts text into the numeric form the
  meaning-match compares. It is surfaced as the `embeddings-backend`, which signs in with an
  Azure-issued identity the service owns (no stored password) via the
  `embeddings-backend-auth="system-assigned"` attribute.
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
