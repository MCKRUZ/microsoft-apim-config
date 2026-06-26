# Caveats — the limits that shaped this design

Every claim here is a real constraint verified against Microsoft Learn (June 2026), not a hedge. A golden copy that hides these would be lying. Read this before you bet production governance on the gateway.

## 1. The monthly budget cap counts per region, not company-wide
The monthly token-budget cap is counted **separately in each region** the gateway runs in. Run the gateway in three regions and a "1,000,000 tokens/month" cap is really 1M *per region* — 3M total. (The older request-counting limits DID sum across regions; this one does not.) A company-wide budget needs per-region math, or a single-region gateway. Single-region is the default here.

## 2. The Consumption tier has no spend controls
`llm-token-limit` and load-balancing are **not available on the Consumption tier**. This repo defaults to **Developer** (cheapest tier that supports the full OpenAI-only showcase) and documents **StandardV2** as the production target. Never put this governance on Consumption — the spend cap simply won't be there.

## 3. One safety check needs a one-time manual step after deploy
The content-safety check signs in using the gateway's own built-in Azure identity (no password). Azure's deployment templates (ARM/Bicep) can't set that sign-in up automatically for this particular connection — verified against the current schema. So it's a one-time manual step:
- Bicep creates the backend **URL-only** (`infra/modules/llm-api.bicep`).
- MI auth is applied **post-deploy** by `scripts/configure-backend-auth.{sh,ps1}`, or by one portal toggle: *Backends → content-safety-backend → Authorization credentials → Managed identity → System assigned → Resource ID `https://cognitiveservices.azure.com`*.
- Until that step runs, content-safety screening returns errors. The smoke test flags this explicitly.

The chat-call and embeddings MI auth do NOT hit this gap — they're handled by the `authentication-managed-identity` policy and the `embeddings-backend-auth` attribute respectively, not the backend entity.

## 4. Content safety is real protection, not a force field
- **Streaming responses:** when a reply is streamed back word-by-word, the check watches a moving window of the text and, if it spots a violation, simply stops sending more — it does **not** return a clean "blocked" error (a 403). The client sees the reply cut off partway, not a tidy rejection.
- **Languages:** the jailbreak / prompt-injection detector (Prompt Shields) is tuned for a limited set of languages and can get it wrong in others.
- **Separate service:** it relies on a standalone Azure AI Content Safety resource wired in behind it (which this repo provisions).

## 5. Semantic caching can return a "close but wrong" answer
The cache reuses a past answer by **matching on meaning, not exact wording**, so if the match is allowed to be too loose (`score-threshold` set too high) it can hand back a reply that is close but not quite right — or out of date, or unsafe for this particular request. Two safeguards are built in: (a) start the threshold tight (`0.05` — lower means a stricter, closer match is required) and loosen it carefully; (b) the safety screen runs **before** the cache is checked, so the incoming text is always screened first. Caching also is not free — it needs its own Redis infrastructure (the cache store).

## 6. RediSearch must be enabled at cache creation
Azure Managed Redis can only enable the **RediSearch** module when the cache is **created** — you cannot add it to an existing cache. `infra/modules/redis.bicep` sets it at creation; changing it later means recreating the cache.

## 7. MCP governance is whole-server, not per-tool
Policies on an MCP server apply to **every** operation/tool the server exposes — you cannot yet scope a policy to one individual tool. Also: never read `context.Response.Body` in an MCP policy; it forces buffering and breaks the streamable-HTTP transport MCP needs.

## 8. Agent-to-agent governance covers requests, not replies
For agent-to-agent (A2A) calls, we can enforce rules on what one agent **sends** to another, but not on the reply coming back — a current platform limit. We still get an audit trail: every call is automatically tagged with the calling agent's ID and name (a standard telemetry tag). A2A also supports only one message format (JSON-RPC).

## 9. Governing Claude requires a v2 tier
Anthropic Messages support for `llm-token-limit` / semantic cache, and the unified doorway's OpenAI⇄Anthropic translation, require an **APIM v2 tier**. This repo is OpenAI-only by design and runs on Developer; adding Claude is a tier upgrade + a backend add — see [runbooks/add-claude.md](runbooks/add-claude.md). It is not a rearchitecture, but it is not free either.

## 10. Preview surfaces will change
MCP, A2A, and the unified model API are **preview**. Their management APIs are still moving and lack stable ARM/Bicep types, which is why they're provisioned via `scripts/provision-preview.*` rather than Bicep ([ADR-0003](adr/0003-preview-via-scripts.md)). Treat them as a direction, not a finished contract; expect to update the scripts as the surfaces stabilise.

## 11. Data masking covers headers and query params — not prompt/completion bodies
The gateway's log-masking can only hide **headers and URL parameters** — verified across every version of the setting. It **cannot** strip personal data (PII) out of the prompt itself or the model's reply. So the `dataMasking` flag does what it can: it hides the credentials (`api-key`/`subscription-key`/`Authorization`) so they never land in logs (`infra/modules/llm-api.bicep`). Protecting the *content* of prompts is a different lever — whether you log the prompt/reply text at all (`promptLogging`): keep that **off** for sensitive business units (the `regulated` profile does), or add a rule that strips personal data out of the logs before they're stored. Bottom line: `dataMasking: true` does **not** scrub prompts — and nothing in the gateway does that automatically.

## 12. Auto-throttling on overspend needs one wiring step
The budget alert (`modules/secops.bicep`) is fully built — it detects overspend and emails you. But an alert only **notifies**; it can't change a setting on its own. To make an overspend automatically tighten the usage limit, you connect the included throttle script (`scripts/throttle.*`) to the alert (via an Azure Automation runbook or Logic App — see [runbooks/secops-loop.md](runbooks/secops-loop.md)). Out of the box you get the alert, the email, and a one-command manual throttle; full automation is a documented wiring step, not a pre-built workflow (deliberately — a hand-rolled workflow is brittle for a reference repo). Also: **Defender for APIs** (threat protection) is billed per subscription, and switching it on for each individual API is a second step in the Azure portal after the plan is enabled.

## 13. Workspaces (federation) need a v2 / Premium tier
Federation means giving each business unit its own walled-off area inside the gateway (a "workspace"). That `workspaces` capability (Phase 4) only runs on the **Basic v2 / Standard v2 / Premium / Premium v2** pricing tiers — verified against the tier feature comparison. The starting setup defaults to **Developer**, which does **not** support workspaces, so deploying with `workspaces: true` on Developer **fails**. Any profile that turns it on (`test`/`prod`/`regulated`) must choose a v2 or Premium tier (`APIM_SKU=StandardV2` or `PremiumV2`). The baseline policy that applies everywhere and `entraAuth` (sign-in) work on every tier; only the workspaces piece carries this requirement. Two more things: a person working inside a workspace needs **two** roles — one scoped to the workspace and one scoped to the whole service — and the preview features (MCP tools and A2A agents) aren't supported inside workspaces yet. See [runbooks/federation.md](runbooks/federation.md).

## 14. Reliability needs Premium-class tiers, and multi-region multiplies the quota
The Phase 5 flags that keep the gateway running through failures come with tier and budget consequences:
- **`availabilityZones`** (surviving a data-center outage within a region) needs Premium / Premium v2; **`multiRegion`** (running in more than one geographic region) needs **Premium (classic) only**. The Developer starting tier supports neither — these flags **fail** on Developer, so enabling them requires `APIM_SKU=Premium`/`PremiumV2`. (`modelFailover` works on any tier.)
- **Multi-region and multi-provider are an either/or today:** Premium classic gives you multi-region but not the v2-only unified front door or Claude; v2 gives you that front door but not multi-region. This is a current Azure limitation — pick based on which matters more ([target-architecture §3](enterprise/target-architecture.md#3-tier-decision-the-load-bearing-choice)).
- **The monthly budget cap counts per region** (see §1): turn on `multiRegion` and a 1M-tokens/month cap becomes 1M × the number of regions. Do the per-region math.
- **Multi-region plus network isolation** needs a network segment (subnet) and a public IP address for each added region, set in the `additionalLocations` objects — these are not filled in automatically. With a single OpenAI account the failover pool has only one member (an auto-cutoff that stops sending traffic to a failing backend — a "circuit breaker" — still protects it); running two regions live at once needs a second region's backend. See [runbooks/reliability.md](runbooks/reliability.md).

## 15. Multi-provider is preview, v2-only, and needs the doorway to fail over
The `multiProvider` capability (the unified front door plus governance for Claude/Gemini) is **not yet final (preview) and v2-only**, so it ships as a guided script ([provision-preview](../scripts/provision-preview.sh)) plus a [runbook](runbooks/multi-provider.md) rather than as Azure deployment templates (Bicep) ([ADR-0009](adr/0009-multi-provider.md)). Three things to know:
- **It rules out multi-region** within a single instance (v2 versus Premium classic — see §14 / §3). To get both, run separate instances behind one shared entry point.
- **Failing over from one provider to another only works through the front door's format translation.** You cannot drop Claude into the Phase-5 OpenAI failover pool and expect it to work — the providers speak different wire formats. Failover between two backends of the *same* provider is the production-ready (generally available, "GA") pool; failover *across* providers goes through the preview front door.
- **The provider's secret key lives in Azure Key Vault** (`useKeyVault`), pointed to by a Key Vault reference that is created after deployment (the secret has to exist before the reference can point at it, so this step can't be pure Bicep). Never put the key directly in a template.

## 16. Cost and SLA reality
Deploying costs real money. **Developer** APIM ≈ $50/mo with **no SLA** and ~30–45 min provisioning. **StandardV2** ≈ several hundred $/mo. Add Azure Managed Redis and Content Safety on top. The repo is deploy-ready; deciding to deploy is a deliberate, cost-incurring action.
