# Caveats — the limits that shaped this design

Every claim here is a real constraint verified against Microsoft Learn (June 2026), not a hedge. A golden copy that hides these would be lying. Read this before you bet production governance on the gateway.

## 1. Token quotas count per gateway region, not globally
The newer `llm-token-limit` token quota is enforced **per gateway instance/region**. Run the gateway in three regions and a "1,000,000 tokens/month" cap is really 1M *per region* — 3M total. (The older request-counting limits DID sum across regions; this one does not.) A company-wide budget needs per-region math, or a single-region gateway. Single-region is the default here.

## 2. The Consumption tier has no spend controls
`llm-token-limit` and load-balancing are **not available on the Consumption tier**. This repo defaults to **Developer** (cheapest tier that supports the full OpenAI-only showcase) and documents **StandardV2** as the production target. Never put this governance on Consumption — the spend cap simply won't be there.

## 3. Content-safety backend managed-identity auth is a known IaC gap
The `llm-content-safety` policy calls the `content-safety-backend` entity as a black box, so the APIM managed identity must live **on the backend entity**. That is **not expressible in the ARM/Bicep backend schema** — verified: even `Microsoft.ApiManagement/service/backends@2025-09-01-preview` `credentials` exposes only `authorization`/`header`/`query`/`certificate`, no managed identity. So:
- Bicep creates the backend **URL-only** (`infra/modules/llm-api.bicep`).
- MI auth is applied **post-deploy** by `scripts/configure-backend-auth.{sh,ps1}`, or by one portal toggle: *Backends → content-safety-backend → Authorization credentials → Managed identity → System assigned → Resource ID `https://cognitiveservices.azure.com`*.
- Until that step runs, content-safety screening returns errors. The smoke test flags this explicitly.

The chat-call and embeddings MI auth do NOT hit this gap — they're handled by the `authentication-managed-identity` policy and the `embeddings-backend-auth` attribute respectively, not the backend entity.

## 4. Content safety is real protection, not a force field
- **Streaming responses:** the policy buffers a sliding window and stops forwarding events on a violation, but does **not** return a 403. Clients see a truncated stream, not a clean block.
- **Languages:** Prompt Shields is tuned for a limited set of languages and can misfire in others.
- **Separate service:** it needs a standalone Azure AI Content Safety resource wired behind it (provisioned here).

## 5. Semantic caching can return a "close but wrong" answer
Caching matches on **vector similarity, not exact text**, so a loose `score-threshold` can hand back an answer that is close but not quite right — or stale, or unsafe for the current request. Two mitigations baked in: (a) start the threshold tight (`0.05` — lower is stricter) and loosen carefully; (b) the safety screen runs **before** the cache lookup, so the incoming prompt is always screened. Caching is also not free — it needs its own Redis infrastructure.

## 6. RediSearch must be enabled at cache creation
Azure Managed Redis can only enable the **RediSearch** module when the cache is **created** — you cannot add it to an existing cache. `infra/modules/redis.bicep` sets it at creation; changing it later means recreating the cache.

## 7. MCP governance is whole-server, not per-tool
Policies on an MCP server apply to **every** operation/tool the server exposes — you cannot yet scope a policy to one individual tool. Also: never read `context.Response.Body` in an MCP policy; it forces buffering and breaks the streamable-HTTP transport MCP needs.

## 8. A2A is JSON-RPC only, request-side governance only
The A2A agent API supports **JSON-RPC** agents only, and does **not** support deserializing outgoing response bodies — so governance lives on the inbound (request) side. Audit comes from the auto-emitted OTel attributes `gen_ai.agent.id` / `gen_ai.agent.name`.

## 9. Governing Claude requires a v2 tier
Anthropic Messages support for `llm-token-limit` / semantic cache, and the unified doorway's OpenAI⇄Anthropic translation, require an **APIM v2 tier**. This repo is OpenAI-only by design and runs on Developer; adding Claude is a tier upgrade + a backend add — see [runbooks/add-claude.md](runbooks/add-claude.md). It is not a rearchitecture, but it is not free either.

## 10. Preview surfaces will change
MCP, A2A, and the unified model API are **preview**. Their management APIs are still moving and lack stable ARM/Bicep types, which is why they're provisioned via `scripts/provision-preview.*` rather than Bicep ([ADR-0003](adr/0003-preview-via-scripts.md)). Treat them as a direction, not a finished contract; expect to update the scripts as the surfaces stabilise.

## 11. Data masking covers headers and query params — not prompt/completion bodies
APIM diagnostic **data masking can only Hide/Mask headers and URL query parameters** — verified against the diagnostic schema across every API version. It **cannot** redact PII inside the LLM prompt or completion **body**. So the `dataMasking` flag does the thing it actually can: it Hides the `api-key`/`subscription-key`/`Authorization` secret-leak vector from telemetry (`infra/modules/llm-api.bicep`). Protecting body content is a *different* lever — the per-API "log LLM messages" toggle (`promptLogging`): leave message-body logging **off** for sensitive BUs (the `regulated` profile does), or run an ingestion-time Log Analytics transform (DCR) to redact before the data lands. Do not assume `dataMasking: true` scrubs prompts — it does not, and nothing in APIM does.

## 12. SecOps auto-throttle needs an actuator you wire
The budget alert (`modules/secops.bicep`) is fully deployed GA — detection, action group, the works. But Azure Monitor alerts **notify**; they don't mutate config. Closing the loop to *enforcement* (lower the TPM cap) is `scripts/throttle.*`, which you wire to the action group via an Automation runbook or Logic App (see [runbooks/secops-loop.md](runbooks/secops-loop.md)). Out of the box you get the alert + email and a one-command throttle; the fully-automatic path is a documented wiring step, not a deployed Logic App (kept out of Bicep deliberately — a hand-rolled workflow JSON is brittle for a reference repo). Also: **Defender for APIs** bills per subscription and onboarding each APIM API to it is a second, recommendation-driven portal step after the plan is enabled.

## 13. Workspaces (federation) need a v2 / Premium tier
The `workspaces` flag (Phase 4 federation) is supported on **Basic v2 / Standard v2 /
Premium / Premium v2 only** — verified against the tier feature comparison. The seed
defaults to **Developer**, which does **not** support workspaces, so deploying
`workspaces: true` on Developer **fails**. Any profile that turns it on (`test`/`prod`/
`regulated`) must set a v2/Premium SKU (`APIM_SKU=StandardV2` or `PremiumV2`). The global
policy floor and `entraAuth` work on every tier; only the workspaces half carries this
requirement. Also: a workspace collaborator needs **both** a workspace-scoped and a
service-scoped role, and MCP/A2A preview surfaces aren't supported inside workspaces yet.
See [runbooks/federation.md](runbooks/federation.md).

## 14. Reliability needs Premium-class tiers, and multi-region multiplies the quota
The Phase 5 gateway-resilience flags carry tier and accounting consequences:
- **`availabilityZones`** needs Premium / Premium v2; **`multiRegion`** needs **Premium
  (classic) only**. The Developer seed supports neither — these flags **fail** on Developer,
  so enabling them requires `APIM_SKU=Premium`/`PremiumV2`. (`modelFailover` works on any tier.)
- **Multi-region vs multi-provider is an either/or today:** Premium classic gives multi-region
  but not the v2-only unified doorway/Claude; v2 gives the doorway but not multi-region. A
  current Azure limit — pick by priority ([target-architecture §3](enterprise/target-architecture.md#3-tier-decision-the-load-bearing-choice)).
- **Token quota counts per region** (see §1): turn on `multiRegion` and a 1M/month cap becomes
  1M × regions. Do the per-region math.
- **Multi-region + network isolation** needs a subnet + public IP per added region in the
  `additionalLocations` objects — not auto-derived. With one OpenAI account the failover pool
  has one member (the circuit breaker still protects it); active-active needs a second region's
  backend. See [runbooks/reliability.md](runbooks/reliability.md).

## 15. Cost and SLA reality
Deploying costs real money. **Developer** APIM ≈ $50/mo with **no SLA** and ~30–45 min provisioning. **StandardV2** ≈ several hundred $/mo. Add Azure Managed Redis and Content Safety on top. The repo is deploy-ready; deciding to deploy is a deliberate, cost-incurring action.
