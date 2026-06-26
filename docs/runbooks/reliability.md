# Runbook — reliability (Phase 5)

Survive a zone, survive a region, survive a flapping model. Three independent layers,
three flags: `availabilityZones` (run across isolated datacenters in a region), `multiRegion` (run live in several regions at once), and `modelFailover` (if a model starts failing or rate-limiting, automatically stop sending it traffic — a "circuit breaker" — and spread calls across a pool of backends).

| Layer | Flag | What it does | Tier |
|---|---|---|---|
| Zone | `availabilityZones` | Spreads the gateway's capacity across isolated datacenters (availability zones) within a region | Premium / Premium v2 |
| Region | `multiRegion` | Runs live gateways in several regions at once, all serving traffic | **Premium (classic) only** |
| Backend | `modelFailover` | An auto-cutoff that stops sending traffic to a failing backend, plus a pool that load-balances across backends | all tiers |

## The load-bearing tier decision (§3)

> **You cannot have both multi-region (Premium classic) and in-gateway multi-provider/Claude (v2) in
> the same instance today.** This is a current Azure limitation, not a design choice.

- **Resilience-first** (global-enterprise scale, low latency worldwide): build on **Premium classic** with
  `multiRegion` + `availabilityZones`, and govern OpenAI inside the gateway. Add Claude later through a
  separate v2 instance or a companion gateway ("sidecar") (`multiProvider`, Phase 6).
- **Provider-independence-first**: build on a **v2** tier (Premium v2), which gives you availability zones plus the single unified
  doorway for multiple model providers — but **no** multi-region until v2 adds it.

The starting template defaults to **Developer**, which supports neither availability zones nor multi-region. Turning on
`availabilityZones`/`multiRegion` therefore **requires changing the tier** — set `APIM_SKU` to
`Premium` (for multi-region) or `PremiumV2` (zones only). Deploying these flags on Developer **fails**.

## Turning it on

```bash
# Zone-redundant single region (Premium v2):
az deployment sub create -l eastus2 -f infra/main.bicep -p infra/main.parameters.json \
  -p profile=prod -p apimSkuName=PremiumV2 -p apimCapacity=3 \
  -p flagOverrides='{"availabilityZones":true}'
# apimCapacity must distribute evenly across zones — 3 units for 3 zones.

# Multi-region active-active (Premium classic):
az deployment sub create -l eastus2 -f infra/main.bicep -p infra/main.parameters.json \
  -p profile=prod -p apimSkuName=Premium -p apimCapacity=3 \
  -p additionalLocations='[{"location":"westus","sku":{"name":"Premium","capacity":3},"zones":["1","2","3"]}]'

# Model failover (any tier — works on the default Developer seed):
az deployment sub create ... -p flagOverrides='{"modelFailover":true}'
```

## How `modelFailover` works

When on, `llm-api.bicep` creates:
- **`chat-backend`** — the Azure OpenAI chat endpoint, set up as a backend with an **auto-cutoff (circuit breaker)**:
  3 failures (429 or 5xx) within 5 minutes trips it off for 1 minute, and it **respects the `Retry-After` header** when
  OpenAI is throttling. A throttling or failing model then fails fast instead of letting requests pile up.
- **`openai-pool`** — a load-balanced `Pool` backend that contains `chat-backend`.

The governed policy routes the chat call through the pool using an injected
`<set-backend-service backend-id="openai-pool" />` (the `FAILOVER_BACKEND` marker in
`llm-governance.xml`). When the flag is off, that marker is removed and the API uses its
plain `serviceUrl` as before — leaving no unused policy behind.

**Single-account caveat:** with just one OpenAI account, the pool has only one member. The auto-cutoff
still protects it (the valuable single-region win). For true active-active redundancy, add a
**second region's OpenAI** as a pool member (with a priority/weight) — and pair it with `multiRegion`
so each gateway region has a nearby backend. The pool is already built to accept that second member.

## ⚠ Interactions to get right

- **The token budget counts per region.** The monthly quota in `llm-token-limit` is enforced **per
  gateway region** ([caveats §1](../caveats.md#1-the-monthly-budget-cap-counts-per-region-not-company-wide)).
  Turn on `multiRegion` and a 1,000,000-token cap effectively becomes 1M **× the number of regions**. Do the per-region
  math, or keep the quota to a single region.
- **Multi-region plus network isolation:** each added region needs its **own subnet and public IP**
  for that region's gateway. When `networkIsolation` is also on, the `additionalLocations` objects must
  carry per-region private-network settings — this isn't filled in automatically. Validate before production.
- **Availability-zone capacity:** units must spread evenly across zones (3 units ↔ 3 zones), or the deploy
  is rejected.
- **Infrastructure changes take 15+ minutes** (adding a region, changing zones) and block other
  infrastructure changes while they run; the gateway keeps serving traffic throughout (except on Developer).

## Verify after deploy
- Portal → APIM → **Locations** → the added regions are listed, each showing its zones.
- Portal → APIM → overview → the primary region shows it is zone-redundant.
- `modelFailover`: APIM → **Backends** → confirm `chat-backend` (with its auto-cutoff rule) and `openai-pool`
  (type Pool, with its member listed). Use "calculate effective policy" on the chat operation to confirm the
  `set-backend-service` pointing at `openai-pool` is present.
- Force throttling (low TPM plus a burst of calls) and watch the auto-cutoff trip → you get fast 5xx responses, then it recovers on its own.
