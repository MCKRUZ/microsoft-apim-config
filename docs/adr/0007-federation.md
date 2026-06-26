# ADR-0007 — Federation: workspaces, a global policy floor, and enforced `<base/>`

**Status:** Accepted · **Date:** 2026-06-25

## Context
Phase 4 of the [target architecture](../enterprise/target-architecture.md) (§5, §9) is the
org-scale model: dozens of business units running their own APIs and agents without losing
central control. The API gateway's (Azure API Management, "APIM") built-in answer is **workspaces** — a walled-off area per business unit —
each with its own access rights (scoped Entra identity permissions, "RBAC"). Central controls are
applied once as a **global policy across all APIs** that every walled-off area automatically pulls
in via the required parent-policy tag, `<base/>`.

## Decision
- **A baseline set of central rules everyone gets** (`modules/governance-global.bicep`), deployed
  in every profile. It carries the platform team's controls (request tracing; sign-in via Entra
  identity tokens — "JWT" — when `entraAuth` is on). It's assembled by **slotting a reusable rule
  snippet into a placeholder** (`<!-- ENTRA_JWT -->`), so when a control is turned off there's no
  leftover dead rule — the same assembly pattern from the toggle catalog, now used for real.
- **A walled-off area per business unit** (`modules/federation.bicep`), each with access rights
  scoped to that area (the **Workspace Contributor** role). Those rights are only granted when a
  real Entra group is supplied, so the demo business units deploy without fake accounts.
- **The `<base/>` parent-rule tag is enforced two ways:** the Phase-2 rules check when policies are
  written, and the built-in Azure Policy `d5448c98-…` (warn by default, can be set to block) at
  deploy and run time. Two layers of defense on the one guarantee that makes this safe — a business
  unit can *add* rules, but can never *remove* the central baseline.
- **Entra sign-in is required globally**, not per API. The identity requirement applies to every
  surface (model, tool, agent), matching §6. The subscription key stays, but only for *tracking who
  used what*; the identity token is what proves *who you are*.

## Honest constraints carried
- **Walled-off areas need a v2 or Premium tier** — confirmed; the default Developer tier does NOT
  support them, so turning on `workspaces: true` on Developer fails. This is called out loudly in
  the module header, the runbook, and [caveats §13](../caveats.md); any profile that enables them
  must set a v2 tier. Bicep can't reject a bad setting combination at build time (that needs an
  experimental feature, `assert`), so this is a documented requirement rather than an automatic
  build check.
- **Turning on `entraAuth` changes what callers must send** — they now need a sign-in token, so the
  key-only smoke test returns "401 unauthorized" on purpose. Called out in the runbook.
- **Workspace gateways / workspace diagnostics** (runtime + logging isolation per BU) are
  deferred — this phase establishes the workspace + RBAC + inheritance model on the default
  managed gateway. YAGNI until a BU needs hard runtime isolation.
- A workspace collaborator needs **both** a workspace-scoped and a service-scoped role; we
  assign the workspace-scoped one and document the service-scoped requirement.

## Consequences
- `dev` is unchanged at runtime except for the benign global floor (base + correlation; no
  JWT). `test`/`prod`/`regulated` gain JWT and (with a v2 SKU) the BU workspaces + enforced
  inheritance.
- New policy assets: `global-governance.xml`, `fragments/entra-jwt.xml`, `workspace-base.xml`.
  Fragments live in `policies/fragments/` so the structural linter (top-level glob) skips them.
- Compiles clean; lint passes (5 top-level policies).
