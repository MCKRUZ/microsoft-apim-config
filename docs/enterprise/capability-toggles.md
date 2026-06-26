# Capability Toggle Catalog

Every governance capability is a switch you can flip. For each one this lists its setting name, whether it is on by default in each environment, which service tier it needs, whether it is production-ready or still in preview, and how it is built. The four environments are **D**=dev, **T**=test, **P**=prod, **R**=regulated. `●` means on by default and `○` means off by default — either can be overridden on any given deployment.

## Platform / hardening toggles

| Flag | Capability | D | T | P | R | Tier req | Maturity | Implemented by |
|---|---|:-:|:-:|:-:|:-:|---|---|---|
| `networkIsolation` | VNet injection, Private Link, public-access OFF, NSGs | ○ | ● | ● | ● | Premium / Premium v2 (injection); Std v2 (integration+PE) | GA | `modules/network.bicep` (new) + `privateEndpoint` per backend |
| `edgeWaf` | Front Door Premium + WAF at the edge | ○ | ○ | ● | ● | any (external resource) | GA | `modules/edge.bicep` (new) |
| `workspaces` | Federated per-BU workspaces + scoped RBAC + `<base/>` Azure Policy | ○ | ○ | ● | ● | Basic v2 / Std v2 / Premium / Premium v2 (**not Developer**) | GA | `modules/federation.bicep` (workspaces + Workspace Contributor RBAC + base-inheritance policy assignment) |
| `entraAuth` | Entra JWT validation at the global (All APIs) scope | ○ | ● | ● | ● | any | GA | `fragments/entra-jwt.xml` spliced into the global policy by `governance-global.bicep` |
| `multiRegion` | Active-active regional gateways + failover | ○ | ○ | ● | ● | **Premium (classic)** only | GA | `additionalLocations` on `apim.bicep` (fails on Developer) |
| `availabilityZones` | Zone-redundant units | ○ | ○ | ● | ● | Premium / Premium v2 | GA | `zones` on `apim.bicep` (capacity must match zone count) |
| `useKeyVault` | Secrets via Key Vault references (home for non-Azure provider keys) | ○ | ● | ● | ● | any | GA | `modules/keyvault.bicep` (vault + APIM MI → Key Vault Secrets User); KV-ref named values added post-deploy |
| `pipelineGuardrails` | CI/CD what-if gate, drift detection, policy tests | ○ | ● | ● | ● | n/a (CI) | GA | pipeline + scheduled drift job |
| `secOpsLoop` | Sentinel, Defender for APIs, budget→auto-throttle, injection-spike alerts | ○ | ○ | ● | ● | any | GA | `modules/secops.bicep` (diag→LAW, Sentinel, action group, 2 log alerts) + `Microsoft.Security/pricings` (sub scope) + `scripts/throttle.*` actuator |
| `selfHostedGateway` | Hybrid / on-prem / multi-cloud gateway | ○ | ○ | ○ | ○ | Developer / Premium | GA | self-hosted gateway resource |

## AI governance control toggles

| Flag | Capability | D | T | P | R | Tier req | Maturity | Implemented by |
|---|---|:-:|:-:|:-:|:-:|---|---|---|
| `tokenRateLimit` | Per-minute TPM cap (runaway protection) | ● | ● | ● | ● | not Consumption | GA | `llm-token-limit` |
| `tokenQuota` | Monthly hard budget (per region) | ● | ● | ● | ● | not Consumption | GA | `llm-token-limit` |
| `preflightReject` | Reject oversize prompts before billing | ● | ● | ● | ● | not Consumption | GA | `estimate-prompt-tokens="true"` |
| `costAttribution` | Per-team/agent token metrics | ● | ● | ● | ● | all | GA | `llm-emit-token-metric` |
| `semanticCache` | Reuse semantically-similar completions | ● | ● | ● | ○* | all (needs Redis) | GA | `llm-semantic-cache-*` + `redis.bicep` |
| `contentSafetyPrompt` | Jailbreak + indirect-injection screen (request) | ● | ● | ● | ● | all | GA | composed `llm-content-safety shield-prompt` |
| `contentSafetyResponse` | Screen completions on the way out | ● | ● | ● | ● | all | GA | composed `enforce-on-completions` |
| `customBlocklists` | Org-specific blocked terms | ○ | ○ | ● | ● | all | GA | `<blocklists>` in policy |
| `promptLogging` | Log prompts/completions for audit | ● | ● | ● | ○* | all | GA | API diagnostic |
| `dataMasking` | Hide secret headers/query in logs (NOT body — see caveats §11) | ○ | ● | ● | ● | all | GA | diagnostic `frontend`/`backend` data-masking in `llm-api.bicep` |
| `mcpTools` | Govern agent→tool (MCP) | ○ | ○ | ● | ● | Dev / v2 / Premium | **Preview** | `provision-preview` + `mcp-governance.xml` |
| `a2aAgents` | Govern agent→agent (A2A) | ○ | ○ | ● | ● | Dev / v2 / Premium | **Preview** | `provision-preview` + `a2a-governance.xml` |
| `multiProvider` | Unified doorway / Claude / Gemini | ○ | ○ | ○ | ○ | **v2 tiers** | **Preview** | `provision-preview.*` guided flow (doorway + Anthropic backend + KV-ref key); informational at Bicep layer via `MULTI_PROVIDER_INTENDED` |
| `modelFailover` | Load-balanced backend pool + circuit breaker | ○ | ● | ● | ● | all | GA | `chat-backend` (circuitBreaker) + `openai-pool` (type Pool) in `llm-api.bicep`, routed via `set-backend-service` |

\* In the `regulated` environment, the semantic cache and the logging of prompt text are both off by default. The cache can return a close-but-wrong answer, and storing raw prompts is a data-protection risk. Turn either on only on purpose — with masking and a tight similarity `score-threshold`.

> The seven production-ready control switches above are **assembled into the policy** at deploy
> time: `llm-api.bicep` drops each element into [`llm-governance.xml`](../../infra/policies/llm-governance.xml)
> only when its switch is on. `customBlocklists` and `promptLogging` are *documented controls*
> (they need configuration set up outside this repo), and `edgeWaf` / `selfHostedGateway` are
> *declared for the future*. The full switch-by-switch audit of how each is wired is in
> [flag-status.md](flag-status.md).

## How the switches depend on each other
- `multiRegion` and `multiProvider` **cannot both be on in one gateway today** — running live in several regions at once needs the Premium classic tier, while governing multiple providers needs v2 (see [target-architecture §3](target-architecture.md#3-tier-decision-the-load-bearing-choice)). The build checks for this and fails if both are set to `true` on one gateway.
- `networkIsolation` (placing the gateway inside a private network) can only be set when the gateway is first created on Premium v2. Changing it later means recreating the gateway.
- `workspaces` needs `entraAuth` turned on, otherwise there is no signed-in identity to scope permissions against.
- The budget-throttle part of `secOpsLoop` writes the `tokens-per-minute` / `token-quota` settings, so it depends on `tokenRateLimit` / `tokenQuota` being on.

## How a flag flows
```
profile/flag (main.parameters) ─► flags object (config/profiles.bicep)
   ├─► conditional module:   module net 'modules/network.bicep' = if (flags.networkIsolation) { ... }
   ├─► conditional policy:   value: replace(loadTextContent('policies/llm-governance.xml'), '<!--JWT-->', flags.entraAuth ? jwtFragment : '')
   └─► resource property:    publicNetworkAccess: flags.networkIsolation ? 'Disabled' : 'Enabled'
```
The policy is built up from whichever switches are on, so a control that is turned off leaves **no** leftover dead policy behind — cleaner than leaving blocks of disabled code commented out.
