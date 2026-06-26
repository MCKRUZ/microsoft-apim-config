# ADR-0009 — Multi-provider: GA Key Vault, preview doorway via script

**Status:** Accepted · **Date:** 2026-06-25

## Context
Phase 6 (target architecture §9, `multiProvider`) is about not being locked to one vendor: one
endpoint that fronts multiple model vendors (a "unified doorway") over OpenAI, Anthropic, and
Google, all governed the same way. It's also the phase with the most caveats — the unified doorway
and governing Anthropic are both **not-yet-final ("preview") and require the v2 tier**, and this
capability sits on the opposite side of the §3 tier either/or from the multi-region support built
in Phase 5 (you can't have both in one instance).

## Decision
- **Split the work by maturity, as established in [ADR-0003](0003-preview-via-scripts.md).**
  - **Production-ready → Bicep:** turn on the long-declared `useKeyVault` flag now
    (`modules/keyvault.bicep`) — stand up Azure's secrets locker (Key Vault) and give the gateway's
    own Azure-issued identity (its managed identity) the *Key Vault Secrets User* permission. This is
    the home a non-Azure provider's API key needs. Phase 6 is its natural trigger: every Azure call
    already signs in with the managed identity (no password), so a third-party key is the first real
    secret to store.
  - **Preview → script + docs:** the unified doorway, the Claude backend, and Anthropic governance
    go in `scripts/provision-preview.*` (extended) and the runbook. `multiProvider` carries no
    deployed infrastructure of its own — it just sets a `MULTI_PROVIDER_INTENDED` output that the
    script reads.
- **Never put the provider's secret in Bicep.** Key Vault holds it; the gateway reads it through a
  pointer to that secret (a Key Vault reference) created after deploy. The gateway checks the pointer
  the moment it's created, so the secret has to exist first — which is also why this pointer can't be
  pure Bicep.
- **Don't fake failover between different providers.** The Phase-5 pool only balances backends that
  speak the same format; switching between OpenAI and Anthropic needs the doorway's translation.
  That's documented, not pooled.

## Honest constraints
- **multiProvider needs the v2 tier and rules out multi-region** in one instance (§3). To get both,
  run two instances behind a single front door (Premium classic for multi-region, v2 for the
  doorway). Stated in the runbook and caveats, with the two-instance layout.
- **Preview features keep changing** — the doorway's setup APIs don't have stable Bicep building
  blocks yet, so the script is guided (portal steps plus `az` commands where stable) and will need
  updates as the feature settles.
- **Ordering of the Key Vault pointer**: the secret has to exist before the pointer is created;
  handled after deploy.

## Consequences
- `useKeyVault` finally does something (test/prod/regulated): a secrets locker plus access for the
  gateway's managed identity, ready for any third-party credential, not just Anthropic.
- `multiProvider` reaches GA-in-Bicep the day Microsoft ships stable types — at which point the
  Anthropic backend + KV-reference named value migrate from the script into `infra/` and this ADR
  updates, exactly as ADR-0003 anticipates.
- Rollout complete: Phases 0–6 done. The remaining frontier is upstream (v2 multi-region), not in
  this repo's control.
