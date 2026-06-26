# Flag wiring status — the consistency audit

Every switch in [`infra/config/profiles.json`](../../infra/config/profiles.json), sorted by
**how it actually works today**. The rule we hold ourselves to: a switch either does something real
(it changes what gets deployed, or what ends up in the policy) or it is *explicitly* put in one of
the not-yet-wired categories below. No switch is allowed to quietly do nothing while looking active.

What the categories mean: **Bicep-gated** = decides whether a piece of infrastructure is deployed
· **Policy-composed** = decides whether a piece of policy is included · **Informational** = states an
intent and drives a script or build step, but by design does not gate any infrastructure ·
**Documented control** = a real control that needs configuration set up outside this repo, not a
clean on/off · **Declared (future)** = a promise of what is coming, not yet built.

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
These are slotted by [`llm-api.bicep`](../../infra/modules/llm-api.bicep) into placeholders in
[`llm-governance.xml`](../../infra/policies/llm-governance.xml). All are on by default, so the
assembled policy matches the always-on starter version of this repo. Turn one off and its piece of
policy simply disappears — nothing dead is left behind.
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
By design these don't control any infrastructure; the build pipeline and the preview features live outside the deployment.
| Flag | Reads it / acts on it |
|---|---|
| `pipelineGuardrails` | declares an env is change-controlled; the pipeline is the `.github/workflows/` + branch/env protection ([runbook](../runbooks/ci-cd-pipeline.md)) |
| `multiProvider` | `MULTI_PROVIDER_INTENDED` output → `provision-preview.*` prints the Claude/doorway flow (preview, v2-only) |
| `mcpTools` | preview MCP-server surface, stood up by `provision-preview.*` (whole-server scope) |
| `a2aAgents` | preview A2A surface, stood up by `provision-preview.*` |

## Documented control — real, needs external config (2)
Being honest about the gap: these aren't a clean on/off you can deploy.
| Flag | Why, and the wiring path |
|---|---|
| `customBlocklists` | Needs a **Content Safety blocklist** created out-of-band + its id in a named value; then add a `<blocklists>` child to the composed `llm-content-safety`. Not injected by default (an empty blocklist id errors at runtime). |
| `promptLogging` | Governs **LLM message-body** capture, which is a per-API LLM-logging / resource-log setting, *not* a policy element. The seed logs token metadata, never bodies (the safe default); turn body capture on deliberately, with `dataMasking` ([caveats §11](../caveats.md)). |

## Declared (future) — forward contract, not built (2)
Listed in the profile so the full set is on the record, but not built yet.
| Flag | Planned |
|---|---|
| `edgeWaf` | Azure Front Door Premium + WAF (`modules/edge.bicep`) — Phase 1b |
| `selfHostedGateway` | self-hosted gateway resource for hybrid/on-prem/multi-cloud |

## Summary
24 switches in total: **16 do something real** (9 control infrastructure + 7 shape the policy),
**4 informational**, **2 documented controls**, **2 declared for the future**. Nothing sits there
doing nothing in secret. The default `dev` profile turns on every production-ready control (matching
the original starter repo); `regulated` is the strict end of the scale (cache and prompt-text
logging both off). The two future switches and the two documented controls are the only places
where "switchable" is still a goal rather than literally true today — and they are called out here
rather than hidden.
