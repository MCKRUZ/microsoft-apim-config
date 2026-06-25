# ADR-0009 — Multi-provider: GA Key Vault, preview doorway via script

**Status:** Accepted · **Date:** 2026-06-25

## Context
Phase 6 (target architecture §9, `multiProvider`) is provider independence: one doorway over
OpenAI + Anthropic + Google, governed identically. It's also the most caveat-heavy phase — the
unified model API and Anthropic governance are **preview and v2-only**, and the capability sits
on the opposite side of the §3 tier trade-off from the multi-region built in Phase 5.

## Decision
- **Split by maturity, as established in [ADR-0003](0003-preview-via-scripts.md).**
  - **GA → Bicep:** wire the long-declared `useKeyVault` flag now (`modules/keyvault.bicep`) —
    Key Vault + APIM MI granted *Key Vault Secrets User*. This is the secret home a non-Azure
    provider key needs; Phase 6 is its natural trigger (every Azure call is keyless via MI, so
    a third-party key is the first real secret).
  - **Preview → script + docs:** the unified doorway + Claude backend + Anthropic governance go
    in `scripts/provision-preview.*` (extended) and the runbook. `multiProvider` is informational
    at the Bicep layer — it sets a `MULTI_PROVIDER_INTENDED` output the script reads.
- **Never put the provider secret in Bicep.** Key Vault holds it; APIM reads it via a
  KV-reference named value created post-deploy (APIM validates the reference on create, so the
  secret must exist first — an ordering reason the named value can't be pure Bicep anyway).
- **Don't fake cross-provider failover.** The Phase-5 pool load-balances same-format backends;
  OpenAI↔Anthropic needs the doorway's translation. Documented, not pooled.

## Honest constraints
- **multiProvider is v2-only and excludes multi-region** in a single instance (§3). For both,
  run separate instances (Premium classic for multi-region, v2/sidecar for the doorway) behind
  one edge. Stated in the runbook + caveats, with the two-instance topology.
- **Preview surfaces move** — the doorway management APIs lack stable Bicep types; the script is
  guided (portal steps + `az` where stable) and will need updates as the surface stabilizes.
- **KV-reference ordering**: secret-before-named-value; handled post-deploy.

## Consequences
- `useKeyVault` finally does something (test/prod/regulated): a vault + APIM MI access, ready for
  any third-party credential, not just Anthropic.
- `multiProvider` reaches GA-in-Bicep the day Microsoft ships stable types — at which point the
  Anthropic backend + KV-reference named value migrate from the script into `infra/` and this ADR
  updates, exactly as ADR-0003 anticipates.
- Rollout complete: Phases 0–6 done. The remaining frontier is upstream (v2 multi-region), not in
  this repo's control.
