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

Two scripts back these and run locally too:
- [`scripts/lint-policies.sh`](../../scripts/lint-policies.sh) / `.ps1` — structural policy lint.
- [`scripts/drift-detect.sh`](../../scripts/drift-detect.sh) / `.ps1` — what-if drift check (exit 2 = drift).

## Why these specific gates

- **Warnings-as-errors on `bicep build`** — the seed compiles clean; this keeps it that way so lint debt can't accrete unnoticed.
- **Structural policy lint, not XML validation** — APIM policy expressions embed C# with nested double quotes (`@(context.Subscription?.Id ?? "anonymous")`), which is *not* well-formed XML. A DOM parser would raise false failures, so the linter checks structure (sections present, `<base />` inheritance, balanced `{{tokens}}`, no hardcoded secrets) instead. The `<base />` check mirrors the Azure Policy *"API Management policies should inherit parent scope using `<base/>`"* — a workspace/BU policy can never silently strip a central control.
- **what-if before every apply** — the resource delta is in the run log before anything mutates; on a PR it's informational, on a deploy it's the plan.
- **smoke-test gates promotion** — `scripts/smoke-test.sh` fires a jailbreak, an over-cap call, and a cache-hit pair at the just-deployed stage. A control regression stops the rollout before it reaches prod.
- **Drift detection** — telemetry can't tell you someone hand-edited a policy in the portal; a scheduled what-if can. Drift fails the job and opens an issue so it's owned, not silently re-applied.

## One-time setup

### 1. Federated identity (OIDC, no stored secrets)

Per environment (`dev`, `test`, `prod`) create an Entra app (or user-assigned MI) with a
**federated credential** trusting this repo's environment, and grant it `Contributor` +
`Role Based Access Control Administrator` (the template assigns roles) on the target
subscription:

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

No client secret is created or stored — auth is the short-lived OIDC token. (rules/security.md)

### 2. GitHub Environments

Create environments `dev`, `test`, `prod`. On `test` and `prod` add a **required reviewers**
protection rule — that is the approval gate. Set these **environment variables** on each:

| Variable | Value |
|---|---|
| `AZURE_CLIENT_ID` | the app/MI client id for that environment |
| `AZURE_TENANT_ID` | tenant id |
| `AZURE_SUBSCRIPTION_ID` | target subscription |
| `AZURE_LOCATION` | region (e.g. `eastus2`) |

### 3. Branch protection

Require the `validate` checks to pass before merge to `main`. Now: PR → validate → review →
merge → staged deploy with approvals → nightly drift watch.

## The `pipelineGuardrails` flag is informational

Unlike `networkIsolation`, this flag does **not** gate a Bicep module — CI/CD lives outside
the deployment. The flag in `profiles.json` is a **declaration** that an environment is
expected to be under pipeline governance (on for `test`/`prod`/`regulated`, off for `dev`).
Use it for audit/compliance assertions ("is this env change-controlled?"), not to switch
infrastructure. Flipping it does not deploy or remove anything. This is called out so no one
expects `pipelineGuardrails: true` to *create* the pipeline — the pipeline is the workflow
files in `.github/`, present once and applied by branch/environment protection.

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

1. Open the `drift` issue / failed run; the log lists the changed resource ids.
2. Decide: was the portal edit legitimate?
   - **No** → redeploy the repo to overwrite it: re-run `deploy.yml` for that environment.
   - **Yes** → reproduce it in `infra/` and open a PR so the repo becomes the source of truth again.
3. Re-run `drift.yml` to confirm green and auto-close the loop.
