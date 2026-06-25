# Runbook: Tune the Semantic Cache

Adjust how aggressively the [semantic cache](../controls/semantic-cache.md) serves
similar prompts. The knob is the `cache-score-threshold` named value, consumed by
`llm-semantic-cache-lookup` in `infra/policies/llm-governance.xml`.

## The knob

`score-threshold`: **lower = stricter** match.

- Default `0.05` — tight. Only near-identical prompts hit.
- Raise it → looser → more hits, more savings, **higher risk** of serving a wrong answer.

## How to change it

Update the `cache-score-threshold` named value (defined in `infra/modules/apim.bicep`),
either via parameters and redeploy, or directly:

```bash
az apim nv update -g rg-<env> --service-name <apim-name> \
  --named-value-id cache-score-threshold --value 0.08
```

## Trade-offs

| Direction        | Effect                          | Risk                                   |
| ---------------- | ------------------------------- | -------------------------------------- |
| Lower (→ 0.05)   | Fewer hits, only close matches  | Lower savings, safest                  |
| Higher (→ 0.1+)  | More hits, more token savings   | **Stale / incorrect / unsafe** answers |

Similarity matching can surface stale or unsafe completions — this is why content safety
screens **before** cache lookup. Loosening the threshold widens that exposure, so tune up
in small steps.

## Confirm hit rate

1. Replay representative prompts via `scripts/smoke-test.{sh,ps1}`.
2. Watch cache hits in **APIM trace** (per-request) and **App Insights** (aggregate).
3. Compare backend token consumption before/after — a higher hit rate shows up as fewer
   backend tokens for the same client traffic.

Tune until the hit rate is acceptable **without** observed wrong answers. Start tight,
loosen gradually.
