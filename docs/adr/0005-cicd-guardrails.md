# ADR-0005 — CI/CD guardrails: reviewed pipeline + drift detection

**Status:** Accepted · **Date:** 2026-06-25

## Context
Principle 5 of the [target architecture](../enterprise/target-architecture.md) is
"policy-as-code, change-controlled — no portal edits in production." That is only real if
two things exist: a pipeline that is the *only* write path to a deployed gateway, and a
detector that catches edits made around it. This is Phase 2 (`pipelineGuardrails`).

## Decision
- **GitHub Actions**, not Azure DevOps — the repo's GitHub-native and `gh` is the standard tool here.
- **OIDC federated credentials**, no stored cloud secrets — a short-lived token per environment (rules/security.md).
- **Staged promotion** `dev → test → prod` via a reusable per-stage workflow; `test`/`prod` are
  GitHub **Environments** with required-reviewer rules — the approval gate is platform-enforced,
  not convention.
- **what-if before every apply**; **smoke-test gates promotion** (a control regression stops the rollout).
- **Scheduled drift detection** runs the repo as a what-if against live environments; mutating
  changes fail the job and open a tracked issue.
- **Structural policy lint, not DOM validation.**

## Rationale for the structural linter
APIM policy XML is not well-formed XML: expression attributes embed C# with nested double
quotes, e.g. `counter-key="@(context.Subscription?.Id ?? "anonymous")"`. `xmllint` / ElementTree
would reject every valid policy. So `scripts/lint-policies.*` checks structure instead — sections
present and closed, `<base />` inheritance in each section, balanced `{{named-value}}` tokens, no
hardcoded secrets. The `<base />` check is the CI mirror of the Azure Policy *"policies should
inherit parent scope using `<base/>`"*, so a BU/workspace policy can't strip a central control —
caught at PR time, not just at runtime.

## The flag is informational, by design
`pipelineGuardrails` does **not** gate a Bicep module — CI/CD is outside the deployment. It is a
declaration that an environment is change-controlled (used for compliance assertions), not an
infrastructure switch. Documented in the [runbook](../runbooks/ci-cd-pipeline.md) so no one
expects flipping it to create the pipeline. The pipeline is the `.github/workflows/` files plus
branch/environment protection.

## Consequences
- Merges to `main` require green `validate`; deploys require approvals; prod has no portal write path.
- One-time setup cost: federated credentials + GitHub Environments + branch protection (runbook §"One-time setup").
- The same lint/drift scripts run locally, so developers catch issues before pushing.
- When workspaces land (Phase 4), the `<base />` lint and the Azure Policy enforce the same
  inheritance invariant from two directions.
