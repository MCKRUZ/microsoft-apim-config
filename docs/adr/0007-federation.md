# ADR-0007 — Federation: workspaces, a global policy floor, and enforced `<base/>`

**Status:** Accepted · **Date:** 2026-06-25

## Context
Phase 4 of the [target architecture](../enterprise/target-architecture.md) (§5, §9) is the
org-scale model: dozens of business units managing their own APIs/agents without losing
central governance. APIM's first-class mechanism is **workspaces** + scoped Entra RBAC,
with central controls applied as a **global (All APIs) policy** that workspaces inherit
via `<base/>`.

## Decision
- **A global policy floor** (`modules/governance-global.bicep`) deployed in every profile.
  It carries the platform-team controls (correlation; Entra JWT when `entraAuth`). Built by
  **splicing a fragment** into a marker (`<!-- ENTRA_JWT -->`) so a disabled control leaves
  no dead policy — the assembly pattern from the toggle catalog, now used for real.
- **Per-BU workspaces** (`modules/federation.bicep`) with workspace-scoped **Workspace
  Contributor** RBAC (assigned only when an Entra group is supplied — demo BUs deploy
  without bogus principals).
- **`<base/>` enforced two ways:** the Phase-2 policy lint at author time, and the built-in
  Azure Policy `d5448c98-…` (Audit by default, Deny optional) at deploy/runtime. Defense in
  depth on the one invariant that makes federation safe — a BU can add policy, never strip
  the central floor.
- **Entra JWT at the global scope**, not per-API. The security-identity floor applies to
  every surface (model/tool/agent), matching §6. Subscription key stays for *attribution*;
  JWT is *identity*.

## Honest constraints carried
- **Workspaces require a v2/Premium tier** — verified; the Developer seed default does NOT
  support them, so `workspaces: true` on Developer fails. Documented loudly in the module
  header, runbook, and [caveats §13](../caveats.md); profiles that enable workspaces must
  set a v2 SKU. Bicep can't fail-fast on a param combination without experimental `assert`,
  so this is a documented precondition, not a compile guard.
- **`entraAuth` on changes the caller contract** to require a bearer token; the key-only
  smoke test returns 401 by design. Called out in the runbook.
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
