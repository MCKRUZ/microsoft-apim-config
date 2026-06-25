# Runbook — reliability (Phase 5)

Survive a zone, survive a region, survive a flapping model. Three independent layers,
three flags: `availabilityZones` (zone redundancy), `multiRegion` (regional failover),
`modelFailover` (backend circuit breaker + load-balanced pool).

| Layer | Flag | What it does | Tier |
|---|---|---|---|
| Zone | `availabilityZones` | `zones` on the gateway — units spread across AZs | Premium / Premium v2 |
| Region | `multiRegion` | `additionalLocations` — active-active regional gateways | **Premium (classic) only** |
| Backend | `modelFailover` | circuit breaker on a chat backend + a load-balanced pool | all tiers |

## The load-bearing tier decision (§3)

> **Multi-region (Premium classic) and in-gateway multi-provider/Claude (v2) are mutually
> exclusive in one instance today.** This is a current Azure limit, not a design choice.

- **Resilience-first** (global-enterprise scale, global latency): anchor on **Premium classic**,
  `multiRegion` + `availabilityZones`, govern OpenAI in-gateway. Add Claude later via a
  separate v2 instance / sidecar (`multiProvider`, Phase 6).
- **Provider-independence-first**: anchor on a **v2** tier (Premium v2), get AZ + the unified
  doorway, but **no** multi-region until v2 ships it.

The seed defaults to **Developer**, which supports neither AZ nor multi-region. Turning on
`availabilityZones`/`multiRegion` therefore **requires a tier change** — set `APIM_SKU` to
`Premium` (for multi-region) or `PremiumV2` (AZ only). Deploying these flags on Developer **fails**.

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
- **`chat-backend`** — the Azure OpenAI chat endpoint as a backend with a **circuit breaker**:
  3 failures (429 or 5xx) in 5 min trips it for 1 min, and it **honours `Retry-After`** on
  OpenAI throttling. A throttling/failing model then fails fast instead of piling up.
- **`openai-pool`** — a load-balanced `Pool` backend containing `chat-backend`.

The governed policy routes the chat call through the pool via an injected
`<set-backend-service backend-id="openai-pool" />` (the `FAILOVER_BACKEND` marker in
`llm-governance.xml`). With the flag off, the marker is removed and the API uses its
`serviceUrl` as before — no dead policy.

**Single-account caveat:** with one OpenAI account the pool has one member. The circuit
breaker still protects it (the valuable single-region win). For true active-active, add a
**second region's OpenAI** as a pool member (priority/weight) — pair it with `multiRegion`
so each gateway region has a near backend. The pool is built ready for that member.

## ⚠ Interactions to get right

- **Token quota counts per region.** `llm-token-limit`'s monthly quota is enforced **per
  gateway region** ([caveats §1](../caveats.md#1-token-quotas-count-per-gateway-region-not-globally)).
  Turn on `multiRegion` and a 1,000,000-token cap becomes 1M **× regions**. Do the per-region
  math, or keep the quota single-region.
- **Multi-region + network isolation:** each added region needs its **own subnet + public IP**
  for the regional gateway. The `additionalLocations` objects must carry per-region VNet config
  when `networkIsolation` is also on — not auto-derived here. Validate before prod.
- **AZ capacity:** units must distribute evenly across zones (3 units ↔ 3 zones), or the deploy
  is rejected.
- **Infra changes take 15+ minutes** (region add, AZ change) and block other infra changes
  meanwhile; the gateway keeps serving (except Developer).

## Verify after deploy
- Portal → APIM → **Locations** → added regions present, each showing its zones.
- Portal → APIM → overview → the primary shows zone redundancy.
- `modelFailover`: APIM → **Backends** → `chat-backend` (circuit breaker rule) + `openai-pool`
  (type Pool, member listed). Calculate effective policy on the chat operation → the
  `set-backend-service` to `openai-pool` is present.
- Force throttling (low TPM + burst) and watch the breaker trip → fast 5xx, then auto-recover.
