# Runbook — CI/CD guardrails (Phase 2)

Makes "policy-as-code" mean something: no change reaches a deployed gateway except
through a reviewed pipeline, and any out-of-band portal edit is caught and surfaced.
This is the `pipelineGuardrails` capability.

## What it adds

| Workflow | Trigger | Does |
|---|---|---|
| [`validate.yml`](../../.github/workflows/validate.yml) | PR touching `infra/`, `scripts/`, workflows | `bicep build` (warnings = errors) · policy lint · secret scan · what-if preview against dev |
| [`deploy.yml`](../../.github/workflows/deploy.yml) → [`_deploy-stage.yml`](../../.github/workflows/_deploy-stage.yml) | push to `main` / manual | staged **dev → test → prod**, each: what-if → deploy → smoke-test; `test`/`prod` gated by required reviewers |
| [`drift.yml`](../../.github/workflows/drift.yml) | nightly cron / manual | what-if the repo against live `test` + `prod`; any mutating change → fail + file a `drift` issue |

Two scripts power these checks, and you can also run them on your own machine:
- [`scripts/lint-policies.sh`](../../scripts/lint-policies.sh) / `.ps1` — checks that each policy file is well-formed.
- [`scripts/drift-detect.sh`](../../scripts/drift-detect.sh) / `.ps1` — runs a dry-run that flags anything changed by hand, outside the pipeline (a "drift" check; exit code 2 means drift was found).

## Why these specific gates

- **Warnings-as-errors on `bicep build`** — the starting template (the "seed") compiles with zero warnings, and this rule keeps it that way so small quality problems can't pile up unnoticed.
- **Structural policy lint, not XML validation** — the gateway's policy rules embed C# code with nested double quotes (`@(context.Subscription?.Id ?? "anonymous")`), so they are *not* valid XML. A strict XML parser would report false failures, so the linter checks structure instead: required sections are present, the `<base />` inheritance tag is there, `{{tokens}}` are balanced, and no secrets are hardcoded. That `<base />` check mirrors the built-in Azure rule *"API Management policies should inherit parent scope using `<base/>`"* — so a business-unit policy can never quietly remove a central control.
- **what-if before every apply** — a dry-run showing exactly what would change is written to the run log before anything is actually changed. On a pull request it's just for information; on a deploy it's the plan that gets applied.
- **smoke-test gates promotion** — `scripts/smoke-test.sh` sends three test calls at the stage just deployed: a jailbreak attempt, a call that exceeds the rate cap, and a pair that should hit the cache. If a control has stopped working, the rollout halts before it reaches production.
- **Drift detection** — telemetry can't tell you someone hand-edited a policy in the portal, but a scheduled dry-run can. When it finds an unauthorized change it fails the job and opens an issue, so the change gets owned and reconciled instead of silently overwritten.

## One-time setup

### 1. Federated identity (OIDC, no stored secrets)

This uses passwordless sign-in with short-lived tokens (OIDC) so no password or key is ever stored. For each environment (`dev`, `test`, `prod`), create an Entra identity (an app, or an Azure-issued identity the service owns) with a **federated credential** that trusts this repo's environment. Grant it the `Contributor` and `Role Based Access Control Administrator` roles on the target subscription (the second role lets the template assign roles itself):

```bash
az ad app create --display-name "apim-gov-deploy-prod"
# Federated credential — subject must match the environment:
az ad app federated-credential create --id <appId> --parameters '{
  "name": "gh-prod",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/<repo>:environment:prod",
  "audiences": ["api://AzureADTokenExchange"]
}'
az role assignment create --assignee <appId> --role Contributor --scope /subscriptions/<subId>
az role assignment create --assignee <appId> --role "Role Based Access Control Administrator" --scope /subscriptions/<subId>
```

No client secret is ever created or stored — the only credential is the short-lived sign-in token. (rules/security.md)

### 2. GitHub Environments

Create environments `dev`, `test`, `prod`. On `test` and `prod`, add a **required reviewers**
protection rule — that is the human approval gate before a deploy proceeds. Set these **environment variables** on each:

| Variable | Value |
|---|---|
| `AZURE_CLIENT_ID` | the app/MI client id for that environment |
| `AZURE_TENANT_ID` | tenant id |
| `AZURE_SUBSCRIPTION_ID` | target subscription |
| `AZURE_LOCATION` | region (e.g. `eastus2`) |

### 3. Branch protection

Require the `validate` checks to pass before anything can merge to `main`. The full path is now: open a pull request → automated validation → human review →
merge → staged deploy with approvals → nightly check for hand-made changes.

## The `pipelineGuardrails` flag is informational

Unlike `networkIsolation`, this flag does **not** turn any infrastructure on or off — the
pipeline lives outside the deployment. In `profiles.json` the flag is simply a **statement**
that an environment is expected to be under pipeline governance (on for `test`/`prod`/`regulated`, off for `dev`).
Use it for audit and compliance questions ("is this environment change-controlled?"), not to switch
infrastructure. Setting it deploys and removes nothing. This is spelled out so no one
expects `pipelineGuardrails: true` to *create* the pipeline — the pipeline is the workflow
files already sitting in `.github/`, present once and enforced by the branch and environment protection rules.

## Running the checks locally

```bash
sh scripts/lint-policies.sh                 # before every push
GOV_PROFILE=prod sh scripts/drift-detect.sh # ad-hoc drift check against live prod
```
```pwsh
pwsh scripts/lint-policies.ps1
$env:GOV_PROFILE='prod'; pwsh scripts/drift-detect.ps1
```

## Handling a drift alert

1. Open the `drift` issue or failed run; the log lists which resources were changed.
2. Decide whether the hand-made edit was legitimate.
   - **No** → redeploy from the repo to overwrite it: re-run `deploy.yml` for that environment.
   - **Yes** → recreate the change in `infra/` and open a pull request, so the repo again matches reality and stays the single source of truth.
3. Re-run `drift.yml` to confirm it passes and closes the loop.
