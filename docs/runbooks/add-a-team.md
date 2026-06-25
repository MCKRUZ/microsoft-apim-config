# Runbook: Add a Team

Onboard a new team to the gateway. A team = an APIM product + subscription; the
**subscription key is the team identity** that every governance control keys off
(token quota counter, cost-attribution dimension, cache vary-by).

See [architecture](../architecture.md).

## Steps

1. Extend the `teams` parameter in `infra/modules/products.bicep` (or the corresponding
   entry in `infra/main.parameters.json`). The repo ships with `team-research` and
   `team-platform`; add your new team alongside them.

   ```bicep
   param teams array = [
     'team-research'
     'team-platform'
     'team-newgroup'   // <-- add
   ]
   ```

2. Redeploy:

   ```bash
   azd up
   # or: az deployment sub create -l <region> -f infra/main.bicep -p infra/main.parameters.json
   ```

3. Retrieve the new team's key (its identity):

   ```bash
   az apim subscription show -g rg-<env> --service-name <apim-name> \
     --sid team-newgroup --query primaryKey -o tsv
   ```

## What you do NOT need to do

- **No policy edits.** `infra/policies/llm-governance.xml` keys every control off
  `context.Subscription.Id`, so a new subscription is automatically rate-limited,
  metered, and cache-isolated.
- Token quota, cost-attribution dimensions, and semantic-cache vary-by all bind to the
  new subscription with no further changes.

## Verify

Run `scripts/smoke-test.{sh,ps1}` with the new key and confirm:

- completions return `200`,
- the team appears as its own series in App Insights (`Subscription` dimension — see
  [cost-attribution](../controls/cost-attribution.md)),
- it cannot read another team's cache ([semantic-cache](../controls/semantic-cache.md)).
