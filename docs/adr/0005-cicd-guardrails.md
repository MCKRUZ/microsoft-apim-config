# ADR-0005 — CI/CD guardrails: reviewed pipeline + drift detection

**Status:** Accepted · **Date:** 2026-06-25

## Context
Principle 5 of the [target architecture](../enterprise/target-architecture.md) says the
gateway's rules live as version-controlled files and only change through a reviewed process —
"no hand edits in the Azure portal in production." That promise is only real if two things
exist: an automated release process that is the *only* way changes reach a live gateway, and a
watchdog that catches any edits someone makes around it. This is Phase 2 (`pipelineGuardrails`).

## Decision
- **GitHub Actions** for the release process, not Azure DevOps — the repo lives on GitHub and `gh` is the standard tool here.
- **No stored cloud passwords.** Each environment signs in with a short-lived, automatically issued token (OIDC federated credentials — see rules/security.md).
- **Step-by-step promotion** `dev → test → prod`, using one reusable workflow per stage. The `test` and `prod` stages are GitHub **Environments** that require a named reviewer to approve — the sign-off gate is enforced by the platform, not just by convention.
- **A dry run before every change** (a "what-if" preview), and a **smoke test that must pass before promotion** — if a control breaks, the rollout stops.
- **A scheduled drift check** compares the version-controlled files against the live environments; any change made outside the process fails the job and opens a tracked issue.
- **A structural rules check, not a strict XML parse** (explained below).

## Rationale for the structural linter
The API gateway's (Azure API Management, "APIM") policy files look like XML but aren't valid XML: the rule expressions embed C# code with
quotes inside quotes, e.g. `counter-key="@(context.Subscription?.Id ?? "anonymous")"`. A standard
XML parser (`xmllint` / ElementTree) would reject every valid policy. So `scripts/lint-policies.*`
checks the structure instead — sections present and closed, each section pulls in its parent rules
via the required `<base />` tag, the `{{named-value}}` placeholders are balanced, and no secrets are
hardcoded. That `<base />` check mirrors the Azure Policy rule *"policies should inherit parent scope
using `<base/>`"*, so a business-unit or walled-off area's rules can't quietly remove a central
control — it's caught when the change is proposed (at pull-request time), not only once it's live.

## The flag is informational, by design
`pipelineGuardrails` does **not** switch on any deployed infrastructure — the release process lives
outside the deployment. The flag simply records that an environment is change-controlled (useful for
compliance statements); it is not an on/off switch for anything built in Azure. This is spelled out
in the [runbook](../runbooks/ci-cd-pipeline.md) so no one expects flipping it to create the release
process. The actual process is the `.github/workflows/` files plus the branch and environment
protection rules.

## Consequences
- Merges to `main` require green `validate`; deploys require approvals; prod has no portal write path.
- One-time setup cost: federated credentials + GitHub Environments + branch protection (runbook §"One-time setup").
- The same lint/drift scripts run locally, so developers catch issues before pushing.
- When the walled-off areas per business unit (workspaces) arrive in Phase 4, the `<base />` check
  and the Azure Policy rule enforce the same inheritance guarantee from two directions.
