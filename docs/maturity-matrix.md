# Maturity matrix — what is GA, what is preview

Before betting production governance on any of this, you need an honest read on how finished each piece is. The **cost and safety core is production-ready (generally available, "GA")**; the layers on top — orchestrating agents and supporting multiple model providers — are still arriving and not yet final ("preview"). This golden copy builds the GA core entirely as infrastructure-as-code, and stands up the preview features through guided steps you run after deployment.

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

- **The production-ready core is fully infrastructure-as-code.** Everything in the GA rows above is deployed and version-controlled in the `infra/` folder. It compiles cleanly and deploys with a single `azd up` command.
- **The preview features are set up by guided steps after deployment.** Tool governance (MCP), agent-to-agent (A2A), and the unified doorway don't have stable, deployable resource definitions in Azure yet, so they are stood up through `scripts/provision-preview.*` (portal and command-line steps plus doc links) rather than faked as code that doesn't really work. See [ADR-0003](adr/0003-preview-via-scripts.md).
- **The status labels are honest, not wishful.** Any preview feature here is marked **PREVIEW** at the top of its doc and may need rework as Microsoft changes it. Know what is actually finished before you build on it.

Source thesis and the original maturity table: `matthewkruczek.ai/blog/apim-agentic-governance`.
