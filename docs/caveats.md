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

## 11. Cost and SLA reality
Deploying costs real money. **Developer** APIM ≈ $50/mo with **no SLA** and ~30–45 min provisioning. **StandardV2** ≈ several hundred $/mo. Add Azure Managed Redis and Content Safety on top. The repo is deploy-ready; deciding to deploy is a deliberate, cost-incurring action.
