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

## Enterprise capabilities — everything is a toggle

Beyond the GA core, the repo is a full **enterprise control plane** built to survive a Dell/T-Mobile-class org: every governance capability is a feature flag with a per-environment default. A `profile` (`dev` / `test` / `prod` / `regulated`) selects a flag set; any flag is overridable per deploy. `dev` reproduces the simple seed; `regulated` turns nearly everything on. A disabled capability leaves **nothing** behind — flags gate conditional module deployment and compose the policy itself.

Six phases, each independently shippable, all on `main`:

| Phase | Capability | Flags | Maturity |
|---|---|---|---|
| 1 | **Network isolation** — VNet injection, Private Link, public-access-off (makes the chokepoint enforced, not honor-system) | `networkIsolation` | GA |
| 2 | **CI/CD guardrails** — reviewed pipeline (`what-if`→approve→apply), policy lint, drift detection | `pipelineGuardrails` | GA |
| 3 | **SecOps loop** — Sentinel, Defender for APIs, budget→auto-throttle, log masking | `secOpsLoop`, `dataMasking` | GA |
| 4 | **Federation** — per-BU workspaces, scoped Entra RBAC, enforced `<base/>` inheritance | `workspaces`, `entraAuth` | GA |
| 5 | **Reliability** — availability zones, multi-region, circuit-breaker backend pool | `availabilityZones`, `multiRegion`, `modelFailover` | GA |
| 6 | **Multi-provider** — Key Vault secret home + unified doorway / Claude | `useKeyVault`, `multiProvider` | GA + Preview |

The enterprise target, the tier decision (multi-region vs multi-provider), and the compliance mapping (EU AI Act / NIST AI RMF / ISO 42001 / 27001 / SOC 2) are in [docs/enterprise/](docs/enterprise/target-architecture.md). The full per-flag wiring audit — what's Bicep-gated, policy-composed, informational, or declared-future — is [docs/enterprise/flag-status.md](docs/enterprise/flag-status.md).

```bash
azd env set GOV_PROFILE prod          # or test / regulated
azd up
# or override one flag on any profile:
az deployment sub create -l eastus2 -f infra/main.bicep -p infra/main.parameters.json \
  -p profile=dev -p flagOverrides='{"networkIsolation":true}'
```

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
| **StandardV2** | several hundred | yes | production target; v2 features (workspaces, VNet integration, Anthropic-ready) |
| **PremiumV2** | more | yes | + availability zones, VNet injection, the unified doorway / multi-provider |
| **Premium** (classic) | more | yes | + **multi-region** active-active (the only tier that has it today) |

Plus Azure Managed Redis and Azure AI Content Safety. The **Consumption** tier is unsupported (no spend controls). Set the tier with `APIM_SKU`. **Multi-region (Premium classic) and the multi-provider doorway (v2) are mutually exclusive in one instance** — see [target-architecture §3](docs/enterprise/target-architecture.md). Workspaces and zones/multi-region need a v2/Premium tier; the Developer seed is single-region.

---

## Maturity legend

🟢 **GA** — implemented as pure Bicep in `infra/`, deploys with `azd up`.
🟡 **Preview** — MCP, A2A, unified doorway: provisioned via `scripts/provision-preview.*` (portal/CLI guidance), because these constructs lack stable Bicep types today. Flagged **PREVIEW** in their docs; expect change.

Full status table: [docs/maturity-matrix.md](docs/maturity-matrix.md).

---

## Repository layout

```
infra/
  main.bicep                 sub-scope orchestrator: flags engine + conditional modules
  main.parameters.json       profile, tier, region, caps, threshold
  config/profiles.json       the feature-flag sets (dev / test / prod / regulated)
  modules/                   monitoring · openai · redis · content-safety · apim · rbac
                             · named-values · llm-api · products            (GA core)
                             · network · private-endpoint                   (Phase 1)
                             · secops                                       (Phase 3)
                             · federation · governance-global               (Phase 4)
                             · keyvault                                     (Phase 6)
  policies/                  llm-governance.xml (marker-composed) · global-governance.xml
                             · workspace-base.xml · mcp/a2a-governance.xml · fragments/
scripts/
  lint-policies.* drift-detect.*   CI guardrails — also run locally (Phase 2)
  throttle.*                       budget→auto-throttle actuator (Phase 3)
  provision-preview.*              content-safety MI + MCP/A2A/unified/Claude guidance
  configure-backend-auth.* smoke-test.* teardown.*
.github/workflows/           validate · deploy (staged, OIDC) · drift (Phase 2)
docs/
  architecture.md · maturity-matrix.md · caveats.md (16 entries)
  enterprise/                target-architecture · capability-toggles · flag-status · compliance-mapping
  controls/ · runbooks/      per-control + per-phase runbooks (network-isolation, ci-cd-pipeline,
                             secops-loop, federation, reliability, multi-provider, …)
  adr/                       0001–0009 (gateway · tier · preview-via-scripts · doorway ·
                             cicd · secops · federation · reliability · multi-provider)
azure.yaml                   azd config + postprovision hook
```

---

## Design decisions worth knowing

- **Keyless** — APIM authenticates to every backend with its system-assigned managed identity; no API keys in policies or config ([rbac.bicep](infra/modules/rbac.bicep)). The first real secret (a non-Azure provider key) lives in Key Vault ([keyvault.bicep](infra/modules/keyvault.bicep)).
- **Everything toggleable** — every capability is a flag; `dev` reproduces the seed, `regulated` is strict. Flags gate module deployment *and* compose the policy itself, so a disabled control leaves no dead policy ([flag-status.md](docs/enterprise/flag-status.md)).
- **The chokepoint is enforced, not honor-system** — with `networkIsolation`, backends have no public path; APIM in the VNet is the only route ([network-isolation runbook](docs/runbooks/network-isolation.md)).
- **Honest maturity** — GA is Bicep; preview (MCP/A2A/unified doorway/Claude) is scripts. The line is never blurred ([ADR-0003](docs/adr/0003-preview-via-scripts.md)).
- **The tier trade-off is surfaced, not hidden** — multi-region (Premium classic) and the v2-only multi-provider doorway can't coexist in one instance; the repo models both as a tier parameter ([target-architecture §3](docs/enterprise/target-architecture.md)).
- **Every caveat is documented** — 16 of them: per-region caps, the content-safety backend-MI IaC gap, data-masking scope, workspace tier reqs, multi-region/multi-provider exclusivity, and more ([docs/caveats.md](docs/caveats.md)).

---

## Verify

`infra/` compiles clean with `bicep build` (no errors, no warnings). After deploy, `scripts/smoke-test.*` empirically proves: governed happy path (200), jailbreak blocked (403), semantic cache hit, and prints how to confirm cost attribution, spend caps, and the preview surfaces. See each [control page](docs/controls/) for per-control verification.
