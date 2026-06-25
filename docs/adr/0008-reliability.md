# ADR-0008 — Reliability: zones, regions, and backend failover as three layers

**Status:** Accepted · **Date:** 2026-06-25

## Context
Phase 5 (target architecture §9) makes the gateway survive failure: a zone, a region, and a
flapping/throttling model. APIM offers three distinct mechanisms at three layers, with
different tier requirements and a hard tier trade-off.

## Decision
- **Treat reliability as three independent flags**, not one: `availabilityZones` (top-level
  `zones`), `multiRegion` (`additionalLocations`), `modelFailover` (backend circuit breaker +
  pool). They compose but are enabled separately — `modelFailover` works on any tier including
  the Developer seed; the gateway-resilience flags need Premium-class.
- **Zones + regions are properties of the existing service** → edited into `apim.bicep`, not a
  new module (they're create/update on the same resource, not standalone resources).
- **`modelFailover` folds into `llm-api.bicep`** — the chat backend + pool are created there
  and the policy is routed through the pool via the same fragment-injection pattern
  (`FAILOVER_BACKEND` marker). Keeping the backends with the policy that references them gets
  the deploy ordering right.
- **Surface the tier trade-off, don't hide it.** Multi-region is Premium-classic-only; the
  unified doorway/Claude is v2-only; you cannot have both in one instance today. Documented in
  the runbook and caveats as the load-bearing tier decision, with a recommendation per priority
  (resilience-first → Premium classic; provider-first → v2).

## Honest constraints
- **AZ/multi-region need a tier change** — the Developer seed supports neither, so these flags
  fail on Developer. Added `Premium` to the allowed SKUs; documented as a precondition (Bicep
  can't fail-fast on a flag/tier mismatch).
- **Token quota counts per region** — `multiRegion` multiplies the effective monthly cap by the
  region count. Cross-referenced to caveats §1; the operator must do the math.
- **Multi-region + network isolation** needs per-region subnet + public IP in each
  `additionalLocations` entry — not auto-derived; flagged validate-before-prod.
- **One OpenAI account → one pool member.** The circuit breaker is the real single-region win;
  true active-active needs a second region's backend added to the pool. The pool is built ready
  for it rather than faking a second member.

## Consequences
- `dev` unchanged (all three flags off). `prod`/`regulated` (with a Premium-class SKU) get zone
  redundancy, multi-region, and the breaker-protected pool; `test` gets `modelFailover`.
- `apim.bicep` gains `zones`/`additionalLocations`; `llm-api.bicep` gains the failover backends
  + policy injection; `llm-governance.xml` gains the `FAILOVER_BACKEND` marker (lint still passes).
- Phase 6 (`multiProvider`) adds a second provider backend to the same pool / a v2 sidecar,
  landing the other side of the tier trade-off.
