# Flag wiring status — the consistency audit

Every flag in [`infra/config/profiles.json`](../../infra/config/profiles.json), classified by
**how it is actually implemented today**. The rule: a flag is either *wired* (it changes what
deploys or what policy is composed) or *explicitly* one of the non-wired categories below — no
flag silently does nothing while pretending otherwise.

Legend: **Bicep-gated** = deploys/omits a resource · **Policy-composed** = includes/omits a
policy element · **Informational** = declares intent, drives a script/CI step, no infra gate by
design · **Documented control** = real control that needs external configuration, not a pure
on/off · **Declared (future)** = forward contract, not yet built.

## Bicep-gated — flips a module/resource (9)
| Flag | Effect | Phase |
|---|---|---|
| `networkIsolation` | VNet + private endpoints + public-access-off | 1 |
| `secOpsLoop` | Sentinel + diag→LAW + alerts + Defender | 3 |
| `dataMasking` | Hide secret headers/query in the diagnostic | 3 |
| `workspaces` | per-BU workspaces + RBAC + `<base/>` policy | 4 |
| `entraAuth` | Entra JWT spliced into the global policy | 4 |
| `availabilityZones` | `zones` on the gateway | 5 |
| `multiRegion` | `additionalLocations` on the gateway | 5 |
| `modelFailover` | circuit-breaker chat backend + pool + route | 5 |
| `useKeyVault` | Key Vault + APIM MI access | 6 |

## Policy-composed — includes/omits a governance element (7)
Composed in [`llm-api.bicep`](../../infra/modules/llm-api.bicep) into the markers in
[`llm-governance.xml`](../../infra/policies/llm-governance.xml). All default **on**, so the
composed policy reproduces the always-on seed; turn one **off** and its element is gone (no dead
policy left behind).
| Flag | Element / attribute |
|---|---|
| `tokenRateLimit` | `llm-token-limit` `tokens-per-minute` |
| `tokenQuota` | `llm-token-limit` `token-quota` (+ period) |
| `preflightReject` | `estimate-prompt-tokens` |
| `costAttribution` | `llm-emit-token-metric` (whole element) |
| `contentSafetyPrompt` | `llm-content-safety` `shield-prompt` |
| `contentSafetyResponse` | `enforce-on-completions` |
| `semanticCache` | `llm-semantic-cache-lookup` + `…-store` |

## Informational — drives a script or CI step, no infra gate (4)
By design these do not gate Bicep; CI/CD and preview surfaces live outside the deployment.
| Flag | Reads it / acts on it |
|---|---|
| `pipelineGuardrails` | declares an env is change-controlled; the pipeline is the `.github/workflows/` + branch/env protection ([runbook](../runbooks/ci-cd-pipeline.md)) |
| `multiProvider` | `MULTI_PROVIDER_INTENDED` output → `provision-preview.*` prints the Claude/doorway flow (preview, v2-only) |
| `mcpTools` | preview MCP-server surface, stood up by `provision-preview.*` (whole-server scope) |
| `a2aAgents` | preview A2A surface, stood up by `provision-preview.*` |

## Documented control — real, needs external config (2)
Honest about the gap: these are not a clean Bicep on/off.
| Flag | Why, and the wiring path |
|---|---|
| `customBlocklists` | Needs a **Content Safety blocklist** created out-of-band + its id in a named value; then add a `<blocklists>` child to the composed `llm-content-safety`. Not injected by default (an empty blocklist id errors at runtime). |
| `promptLogging` | Governs **LLM message-body** capture, which is a per-API LLM-logging / resource-log setting, *not* a policy element. The seed logs token metadata, never bodies (the safe default); turn body capture on deliberately, with `dataMasking` ([caveats §11](../caveats.md)). |

## Declared (future) — forward contract, not built (2)
Present in the profile so the contract is complete; no implementation yet.
| Flag | Planned |
|---|---|
| `edgeWaf` | Azure Front Door Premium + WAF (`modules/edge.bicep`) — Phase 1b |
| `selfHostedGateway` | self-hosted gateway resource for hybrid/on-prem/multi-cloud |

## Summary
24 flags: **16 wired** (9 Bicep-gated + 7 policy-composed), **4 informational**, **2 documented
controls**, **2 declared-future**. Nothing is silently inert. The default `dev` profile turns on
every GA control (reproducing the original seed); `regulated` is the strict end (cache + prompt
bodies off). The two declared-future flags and the two documented controls are the only places
"toggleable" is aspirational rather than literal — called out here rather than hidden.
