# Runbook — federation with workspaces (Phase 4)

Central control, BU autonomy. The platform team owns the gateway, the global policy
floor, and the audit plane; each business unit gets a **workspace** — its own APIs,
products, subscriptions, settings — with permissions (role-based access control) scoped to just that workspace, governed through Entra ID (Azure's identity service).
Flags: `workspaces` (the per-business-unit containers) and `entraAuth` (require a verified Entra sign-in token — a "JWT" — on every call).

## What it deploys

| When | Resource | Purpose |
|---|---|---|
| always | `modules/governance-global.bicep` → service `policy` | The **minimum rules that apply to every API**, which all other scopes inherit through the `<base />` tag: a correlation header, plus (when `entraAuth` is on) checking the Entra sign-in token. |
| `entraAuth` on | named values `entra-tenant-id`, `entra-audience` | The tenant and audience the sign-in token is checked against. |
| `workspaces` on | `modules/federation.bicep` → N workspaces | One workspace per business unit (default: retail, networkops, finance). |
| `workspaces` on | workspace `policy` (`<base />`) | Each business unit inherits the central minimum rules. |
| `workspaces` on | role assignment (Workspace Contributor) | Permissions scoped to one business unit, granted when you supply an Entra group. |
| `workspaces` on | Azure Policy assignment `apim-base-inheritance` | Built-in rule `d5448c98-…` that audits or blocks any policy that drops `<base/>`. |

## ⚠ Tier requirement — workspaces need a v2 / Premium tier

Workspaces only work on the **Basic v2 / Standard v2 / Premium / Premium v2** tiers —
**not** the Developer tier the starting template defaults to. (This is confirmed against the tier feature
comparison.) **Deploying `workspaces: true` on Developer will fail.** So any profile
that turns workspaces on (`test`/`prod`/`regulated`) must also set a v2 or Premium tier:

```bash
azd env set GOV_PROFILE prod
azd env set APIM_SKU StandardV2     # or PremiumV2 — NOT Developer
azd up
```
The central `governance-global` minimum rules (including `entraAuth`) work on **every** tier; only the
workspaces half carries this tier requirement.

## The federation contract (why `<base/>` matters)

```
Global (All APIs) policy   ── platform team owns ──►  <base/> + correlation + [Entra JWT]
        ▲ inherited by
Workspace policy (per BU)   ── BU team owns ───────►  <base/>  + (BU may ADD narrower rules)
```

A workspace team can **add** policies but cannot **remove** the central ones, because the
`<base/>` tag pulls the parent's rules in. The built-in Azure rule enforces this from the
outside: if someone drops `<base/>`, the policy is flagged for audit (or **blocked outright**, if you set
`basePolicyEffect=Deny`). Two independent mechanisms guard the same rule — the
check for `<base/>` in the pipeline (Phase 2) when a policy is written, and the Azure rule at deploy and run time.

## Wiring BU RBAC

By default, workspaces are created **without** any permission assignments (the demo business units have no real
Entra groups). To give a business-unit team access scoped to just their workspace, put the unit's Entra **group object id** in
the workspace definition and redeploy:

```bash
az deployment sub create -l eastus2 -f infra/main.bicep \
  -p infra/main.parameters.json -p profile=prod -p apimSkuName=StandardV2 \
  -p workspaceDefs='[{"name":"retail","displayName":"Retail","description":"Retail BU","adminGroupId":"<group-object-id>"}]'
```
This module grants the **API Management Workspace Contributor** role (`0c34c906-…`) scoped to the
workspace. In Microsoft's model, a collaborator **also needs a second role at the service level**
(`API Management Service Workspace API Developer` or `…Product Manager`) —
assign that separately, since it provides the cross-cutting read access the workspace-scoped role doesn't. For production, build custom roles that grant only the minimum needed.

## Entra JWT (the `entraAuth` flag)

When this is on, the central policy requires a valid Entra ID sign-in token (`Authorization: Bearer …`)
for the configured audience on **every** API. Set the tenant and audience:

```bash
az deployment sub create ... -p profile=test \
  -p entraTenantId=<tenant-guid> -p entraAudience='api://apim-ai-gateway'
```
`entraTenantId` defaults to the **tenant you deploy from**; `entraAudience` defaults to
`api://apim-ai-gateway` — set it to your app registration's Application ID URI.

> **Smoke test note:** `scripts/smoke-test.*` sends only a subscription key. With
> `entraAuth` on it will get a **401** (unauthorized) until you also send a bearer token — and that's the
> intended behavior (the subscription key says which team is calling; the sign-in token proves who they are). Run
> the smoke test against a `dev`-profile deploy, or extend it to fetch a token first.

## Verify after deploy

- Portal → APIM → **Workspaces** → the BU workspaces are listed.
- Portal → APIM → workspace → **Policies** → the `<base/>` policy is present.
- Portal → **Policy** → Assignments → `apim-base-inheritance` present (Audit/Deny).
- With `entraAuth` on: a call with only a key returns **401**; a call with a valid token for the
  audience returns **200**.
- Use the portal's "calculate effective policy" on a workspace API to confirm it inherits the central rules.

## Honest constraints
- **Per-business-unit runtime isolation** (a dedicated "workspace gateway") and **per-workspace
  logging settings** are extra resources not deployed here — this phase
  sets up the workspace, scoped permissions, and inheritance model on the shared managed gateway.
  Add a dedicated workspace gateway when a mission-critical business unit needs its own isolated runtime.
- Provisioning a dedicated **workspace gateway can take hours**; plan business-unit onboarding accordingly.
- The preview features — the standard agents use to reach tools (MCP) and agent-to-agent (A2A) — are **not yet supported inside workspaces**, so keep those at
  the service level for now.
