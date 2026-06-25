# Maturity matrix — what is GA, what is preview

A clear-eyed reading of maturity is required before betting production governance on any of this. The **cost and safety core is production-ready**; the orchestration and multi-provider layers on top are still arriving. This golden copy implements the GA core as pure Bicep and the preview surfaces as guided post-deploy provisioning.

| Capability | Status | This repo | What to know |
|---|---|---|---|
| Token limits (spend caps) | **GA** | `llm-governance.xml` + `named-values.bicep` | Not on the Consumption tier. Quota counts **per gateway region**. |
| Content safety screening | **GA** | `llm-governance.xml` + `content-safety.bicep` | Limited on streaming responses; tuned for a handful of languages; needs a separate Content Safety resource. Backend MI auth is a [known IaC gap](caveats.md). |
| Semantic caching | **GA** | `llm-governance.xml` + `redis.bicep` | Needs Azure Managed Redis with **RediSearch** (enabled at creation only). Similarity match can surface stale answers. |
| Cost tracking & tagging | **GA** | `llm-emit-token-metric` → App Insights | Max 5 custom dimensions per policy. |
| Per-team identity | **GA** | `products.bicep` | Subscription key = team/app identity; spend + metrics keyed on it. |
| Keyless backend auth (MI) | **GA** | `rbac.bicep` | System-assigned identity; `Cognitive Services OpenAI User` + `Cognitive Services User`. |
| Turning APIs into agent tools (MCP) | **Preview** | `provision-preview.*` + `mcp-governance.xml` | Whole-server policy scope, not per-tool. |
| Agent-to-agent traffic (A2A) | **Preview** | `provision-preview.*` + `a2a-governance.xml` | JSON-RPC only; no response-body deserialization. |
| One doorway (unified model API) | **Preview** | `provision-preview.*` | OpenAI⇄Anthropic translation; rolling out; adding Claude needs StandardV2. |
| Governing Claude through the gateway | **v2 tiers only** | documented path | Not implemented (OpenAI-only by design); see [runbooks/add-claude.md](runbooks/add-claude.md). |

## Why the split matters for this repo

- **GA core = Infrastructure as Code.** Everything in the GA rows above is deployed and version-controlled in `infra/` Bicep. It compiles clean and deploys with `azd up`.
- **Preview surfaces = guided post-deploy.** MCP, A2A, and the unified doorway lack stable ARM/Bicep resource types today, so they are provisioned through `scripts/provision-preview.*` (portal/CLI steps + doc links) rather than faked as Bicep. See [ADR-0003](adr/0003-preview-via-scripts.md).
- **The maturity legend is honest, not aspirational.** A preview feature here is labelled **PREVIEW** at the top of its doc and may need rework as Microsoft changes the surface. Know what is finished before you build on it.

Source thesis and the original maturity table: `matthewkruczek.ai/blog/apim-agentic-governance`.
