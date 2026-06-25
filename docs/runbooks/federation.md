# Runbook — federation with workspaces (Phase 4)

Central control, BU autonomy. The platform team owns the gateway, the global policy
floor, and the audit plane; each business unit gets a **workspace** — its own APIs,
products, subscriptions, settings — with permissions (role-based access control) scoped to just that workspace, governed through Entra ID (Azure's identity service).
Flags: `workspaces` (the per-business-unit containers) and `entraAuth` (require a verified Entra sign-in token — a "JWT" — on every call).

## What it deploys

| When | Resource | Purpose |
|---|---|---|
| always | `modules/governance-global.bicep` → service `policy` | The **All-APIs floor** every scope inherits via `<base />`. Correlation header + (when `entraAuth`) Entra JWT validation. |
| `entraAuth` on | named values `entra-tenant-id`, `entra-audience` | Tenant + audience the JWT fragment validates against. |
| `workspaces` on | `modules/federation.bicep` → N workspaces | One per BU (default: retail, networkops, finance). |
| `workspaces` on | workspace `policy` (`<base />`) | Each BU inherits the global floor. |
| `workspaces` on | role assignment (Workspace Contributor) | Scoped RBAC, per BU, when an Entra group is supplied. |
| `workspaces` on | Azure Policy assignment `apim-base-inheritance` | Built-in `d5448c98-…` audits/denies any policy that drops `<base/>`. |

## ⚠ Tier requirement — workspaces need a v2 / Premium tier

Workspaces are supported on **Basic v2 / Standard v2 / Premium / Premium v2 only** —
**not** the Developer tier the seed defaults to. Verified against the tier feature
comparison. **Deploying `workspaces: true` on Developer will fail.** So any profile
that turns workspaces on (`test`/`prod`/`regulated`) must also set a v2/Premium SKU:

```bash
azd env set GOV_PROFILE prod
azd env set APIM_SKU StandardV2     # or PremiumV2 — NOT Developer
azd up
```
The `governance-global` floor (incl. `entraAuth`) works on **every** tier; only the
workspaces half carries the tier requirement.

## The federation contract (why `<base/>` matters)

```
Global (All APIs) policy   ── platform team owns ──►  <base/> + correlation + [Entra JWT]
        ▲ inherited by
Workspace policy (per BU)   ── BU team owns ───────►  <base/>  + (BU may ADD narrower rules)
```

A workspace team can **add** policies but cannot **remove** the central ones, because
`<base/>` pulls the parent scope in. The built-in Azure Policy enforces this from the
outside: drop `<base/>` and the policy is **audited** (or **denied**, if you set
`basePolicyEffect=Deny`). Two independent mechanisms guarding the same invariant — the
`<base/>`-presence lint in CI (Phase 2) at author time, and Azure Policy at deploy/runtime.

## Wiring BU RBAC

By default workspaces are created **without** RBAC assignments (the demo BUs have no real
Entra groups). To grant a BU team scoped access, put the BU's Entra **group object id** in
the workspace def and redeploy:

```bash
az deployment sub create -l eastus2 -f infra/main.bicep \
  -p infra/main.parameters.json -p profile=prod -p apimSkuName=StandardV2 \
  -p workspaceDefs='[{"name":"retail","displayName":"Retail","description":"Retail BU","adminGroupId":"<group-object-id>"}]'
```
This module assigns **API Management Workspace Contributor** (`0c34c906-…`) at the
workspace scope. Per Microsoft's model a collaborator **also needs a service-scoped
workspace role** (`API Management Service Workspace API Developer` / `…Product Manager`)
assigned at the service scope — assign that separately (it grants the cross-cutting read
access workspace roles don't). Custom least-privilege roles are the production path.

## Entra JWT (the `entraAuth` flag)

When on, the global policy requires a valid Entra ID token (`Authorization: Bearer …`)
for the configured audience on **every** API. Configure tenant + audience:

```bash
az deployment sub create ... -p profile=test \
  -p entraTenantId=<tenant-guid> -p entraAudience='api://apim-ai-gateway'
```
`entraTenantId` defaults to the **deploying tenant**; `entraAudience` defaults to
`api://apim-ai-gateway` — set it to your app registration's Application ID URI.

> **Smoke test note:** `scripts/smoke-test.*` calls with a subscription key only. With
> `entraAuth` on it will get **401** until you also send a bearer token — that's the
> intended posture (subscription key = team attribution; JWT = security identity). Run
> the smoke test against a `dev`-profile deploy, or extend it to fetch a token.

## Verify after deploy

- Portal → APIM → **Workspaces** → the BU workspaces are listed.
- Portal → APIM → workspace → **Policies** → the `<base/>` policy is present.
- Portal → **Policy** → Assignments → `apim-base-inheritance` present (Audit/Deny).
- With `entraAuth` on: a key-only call returns **401**; a call with a valid token for the
  audience returns **200**.
- Calculate effective policy on a workspace API → confirm the global floor is inherited.

## Honest constraints
- **Workspace gateways** (runtime isolation per BU) and **workspace-level diagnostic
  settings** (federated logging) are additional resources not deployed here — this phase
  establishes the workspace + RBAC + inheritance model on the default managed gateway.
  Add workspace gateways when a mission-critical BU needs runtime isolation.
- Workspace **gateway provisioning can take hours**; plan BU onboarding accordingly.
- MCP/A2A preview surfaces are **not yet supported inside workspaces** — keep those at
  the service scope for now.
