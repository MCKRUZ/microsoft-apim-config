# Capability Toggle Catalog

Every governance capability as a feature flag: its parameter, default per profile, tier requirement, maturity, and how it's implemented. Profiles: **D**=dev, **T**=test, **P**=prod, **R**=regulated. `●`=on, `○`=off by default (always overridable per deploy).

## Platform / hardening toggles

| Flag | Capability | D | T | P | R | Tier req | Maturity | Implemented by |
|---|---|:-:|:-:|:-:|:-:|---|---|---|
| `networkIsolation` | VNet injection, Private Link, public-access OFF, NSGs | ○ | ● | ● | ● | Premium / Premium v2 (injection); Std v2 (integration+PE) | GA | `modules/network.bicep` (new) + `privateEndpoint` per backend |
| `edgeWaf` | Front Door Premium + WAF at the edge | ○ | ○ | ● | ● | any (external resource) | GA | `modules/edge.bicep` (new) |
| `workspaces` | Federated per-BU workspaces + scoped RBAC + `<base/>` Azure Policy | ○ | ○ | ● | ● | Basic v2 / Std v2 / Premium / Premium v2 (**not Developer**) | GA | `modules/federation.bicep` (workspaces + Workspace Contributor RBAC + base-inheritance policy assignment) |
| `entraAuth` | Entra JWT validation at the global (All APIs) scope | ○ | ● | ● | ● | any | GA | `fragments/entra-jwt.xml` spliced into the global policy by `governance-global.bicep` |
| `multiRegion` | Active-active regional gateways + failover | ○ | ○ | ● | ● | **Premium (classic)** only | GA | `additionalLocations` on `apim.bicep` |
| `availabilityZones` | Zone-redundant units | ○ | ○ | ● | ● | Premium / Premium v2 | GA | `zones` on `apim.bicep` |
| `useKeyVault` | Secrets via Key Vault references | ○ | ● | ● | ● | any | GA | `modules/keyvault.bicep` + KV-ref named values |
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
| `contentSafetyPrompt` | Jailbreak + indirect-injection screen (request) | ○ | ● | ● | ● | all | GA | `llm-content-safety shield-prompt` |
| `contentSafetyResponse` | Screen completions on the way out | ○ | ● | ● | ● | all | GA | `enforce-on-completions="true"` |
| `customBlocklists` | Org-specific blocked terms | ○ | ○ | ● | ● | all | GA | `<blocklists>` in policy |
| `promptLogging` | Log prompts/completions for audit | ● | ● | ● | ○* | all | GA | API diagnostic |
| `dataMasking` | Hide secret headers/query in logs (NOT body — see caveats §11) | ○ | ● | ● | ● | all | GA | diagnostic `frontend`/`backend` data-masking in `llm-api.bicep` |
| `mcpTools` | Govern agent→tool (MCP) | ○ | ○ | ● | ● | Dev / v2 / Premium | **Preview** | `provision-preview` + `mcp-governance.xml` |
| `a2aAgents` | Govern agent→agent (A2A) | ○ | ○ | ● | ● | Dev / v2 / Premium | **Preview** | `provision-preview` + `a2a-governance.xml` |
| `multiProvider` | Unified doorway / Claude / Gemini | ○ | ○ | ○ | ○ | **v2 tiers** | **Preview** | unified model API (v2 or sidecar) |
| `modelFailover` | Load-balanced backend pools + circuit breaker | ○ | ● | ● | ● | all | GA | backend `Pool` + `circuitBreaker` |

\* In `regulated`, semantic cache and prompt-body logging default **off**: cache can surface a close-but-wrong answer, and raw prompt logging is a data-protection liability. Turn on deliberately with masking + tight `score-threshold`.

## Notes on dependencies
- `multiRegion` and `multiProvider` are **mutually exclusive in one instance today** (Premium classic vs v2 — see [target-architecture §3](target-architecture.md#3-tier-decision-the-load-bearing-choice)). The flag set validates this and fails the build if both are `true` on one instance.
- `networkIsolation` via injection is **create-time only** on Premium v2 — changing it later requires recreating the instance.
- `workspaces` requires `entraAuth` for meaningful RBAC scoping.
- `secOpsLoop` budget→throttle writes the `tokens-per-minute` / `token-quota` named values, so it depends on `tokenRateLimit`/`tokenQuota`.

## How a flag flows
```
profile/flag (main.parameters) ─► flags object (config/profiles.bicep)
   ├─► conditional module:   module net 'modules/network.bicep' = if (flags.networkIsolation) { ... }
   ├─► conditional policy:   value: replace(loadTextContent('policies/llm-governance.xml'), '<!--JWT-->', flags.entraAuth ? jwtFragment : '')
   └─► resource property:    publicNetworkAccess: flags.networkIsolation ? 'Disabled' : 'Enabled'
```
Policy fragments are assembled from toggles so a disabled control leaves **no** dead policy in the pipeline (cleaner than commented blocks).
