# APIM Agentic Governance — Golden Copy

A canonical, deployable reference implementation of **Azure API Management as the governance layer for AI agents**: the single chokepoint in front of every model call, tool invocation, and agent-to-agent hand-off.

> The trust boundary moved. Model-level safety governs the words a model produces; it cannot govern what an agent *does*. The controls that matter — who may act, how much they may spend, which systems they reach, and a record of everything they did — live at the one point every action crosses: the API gateway.
>
> Based on [*The Trust Boundary Moved: APIM as Your Agentic Governance Layer*](https://matthewkruczek.ai/blog/apim-agentic-governance).

This repo is **Infrastructure as Code + deep docs** — not slideware. Clone it, `azd up`, and you have a fully governed AI gateway.

---

## What it governs

One control plane (APIM), three traffic surfaces:

| Surface | Governed by | Status |
|---|---|---|
| **agent → model** | token spend caps, content safety, semantic cache, per-team cost attribution | **GA** |
| **agent → tool** (MCP) | rate limit, identity, agent-id audit trace | Preview |
| **agent → agent** (A2A) | rate limit, identity, OTel agent attribution | Preview |
| **one doorway** (unified model API) | the same policies, across providers | Preview |

The four GA controls, applied as one ordered policy ([`infra/policies/llm-governance.xml`](infra/policies/llm-governance.xml)):

1. **Spend cap** — `llm-token-limit`: per-minute TPM rate + monthly quota, with pre-flight prompt estimation so rejected calls never bill the model.
2. **Cost attribution** — `llm-emit-token-metric`: per-team / per-agent token metrics into Application Insights.
3. **Content safety** — `llm-content-safety` (Prompt Shields): blocks jailbreaks and indirect prompt-injection before the model, request and response.
4. **Semantic cache** — `llm-semantic-cache-*`: returns cached completions for semantically similar prompts (Redis + RediSearch).

See [docs/architecture.md](docs/architecture.md) for the two-plane model and [docs/diagrams/request-flow.md](docs/diagrams/request-flow.md) for the request pipeline.

---

## Quickstart

**Prerequisites:** an Azure subscription with quota for APIM + Azure OpenAI + Content Safety, the [`az` CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), and [`azd`](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd). `az login` first.

```bash
azd auth login
azd up                       # provisions GA core, then runs the preview-provisioning hook
./scripts/smoke-test.sh      # proves each control against the live deploy  (smoke-test.ps1 on Windows)
```

`azd up` will prompt for an environment name, region, and publisher email. The default SKU is **Developer** (cheapest, runs the whole OpenAI-only showcase). After it completes, the gateway URL and resource names are in the deployment outputs.

**Fallback without azd:**
```bash
az deployment sub create -l eastus2 -f infra/main.bicep -p infra/main.parameters.json
./scripts/provision-preview.sh   # configure content-safety MI + preview guidance
```

Full steps, prerequisites, and the soft-delete purge note: [docs/runbooks/deploy.md](docs/runbooks/deploy.md).

---

## Cost & SLA reality

Deploying costs real money — this is a deliberate, cost-incurring action, **not performed for you**.

| Tier | ~Cost/mo | SLA | Use |
|---|---|---|---|
| **Developer** (default) | ~$50 | **none** | reference / demo — runs the full OpenAI-only showcase incl. previews |
| **StandardV2** | several hundred | yes | production target; Anthropic-ready |
| PremiumV2 | more | yes | multi-region / VNet (then per-region token-cap math applies) |

Plus Azure Managed Redis and Azure AI Content Safety. The **Consumption** tier is unsupported (no spend controls). Set the tier with `APIM_SKU`.

---

## Maturity legend

🟢 **GA** — implemented as pure Bicep in `infra/`, deploys with `azd up`.
🟡 **Preview** — MCP, A2A, unified doorway: provisioned via `scripts/provision-preview.*` (portal/CLI guidance), because these constructs lack stable Bicep types today. Flagged **PREVIEW** in their docs; expect change.

Full status table: [docs/maturity-matrix.md](docs/maturity-matrix.md).

---

## Repository layout

```
infra/
  main.bicep                 sub-scope orchestrator (RG + modules + RBAC)
  main.parameters.json       tier (default Developer), region, caps, threshold
  modules/                   monitoring · openai · redis · content-safety · apim
                             · rbac · named-values · llm-api · products
  policies/                  llm-governance.xml · mcp-governance.xml · a2a-governance.xml
scripts/
  provision-preview.*        post-deploy: content-safety MI + MCP/A2A/unified guidance
  configure-backend-auth.*   content-safety backend managed-identity (ARM-schema gap)
  smoke-test.*               8 control proofs against a live deploy
  teardown.*                 destructive: delete the resource group
docs/
  architecture.md · maturity-matrix.md · caveats.md
  controls/                  one page per control (what · policy · wiring · verify · caveats)
  runbooks/                  deploy · add-a-team · tune-cache · onboard-a-tool · add-claude
  adr/                       0001 APIM-as-gateway · 0002 Developer-default · 0003 preview-via-scripts · 0004 unified-doorway
  diagrams/                  request-flow (Mermaid)
azure.yaml                   azd config + postprovision hook
```

---

## Design decisions worth knowing

- **Keyless** — APIM authenticates to every backend with its system-assigned managed identity; no API keys in policies or config ([rbac.bicep](infra/modules/rbac.bicep)).
- **Honest maturity** — GA is Bicep; preview is scripts. The line is never blurred ([ADR-0003](docs/adr/0003-preview-via-scripts.md)).
- **OpenAI-only, multi-provider-ready** — the unified doorway is built but points at Azure OpenAI; adding Claude is a tier + backend change, not a rearchitecture ([ADR-0004](docs/adr/0004-unified-doorway-openai-only.md), [add-claude](docs/runbooks/add-claude.md)).
- **Every caveat is documented** — per-region caps, the content-safety backend-MI IaC gap, streaming/language limits, cache staleness, and more: [docs/caveats.md](docs/caveats.md).

---

## Verify

`infra/` compiles clean with `bicep build` (no errors, no warnings). After deploy, `scripts/smoke-test.*` empirically proves: governed happy path (200), jailbreak blocked (403), semantic cache hit, and prints how to confirm cost attribution, spend caps, and the preview surfaces. See each [control page](docs/controls/) for per-control verification.
