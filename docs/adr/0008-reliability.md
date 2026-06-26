# ADR-0008 — Reliability: zones, regions, and backend failover as three layers

**Status:** Accepted · **Date:** 2026-06-25

## Context
Phase 5 (target architecture §9) makes the gateway survive failures at three levels: losing one
data center within a region (a "zone"), losing a whole region, and a model backend that keeps
failing or rate-limiting. The API gateway (Azure API Management, "APIM") handles each level with a different mechanism, each with its own
tier requirement — and there's a hard either/or tier trade-off between them.

## Decision
- **Treat reliability as three independent switches**, not one: `availabilityZones` (spread across
  data centers in a region), `multiRegion` (run in more than one region), and `modelFailover` (an
  auto-cutoff for a failing model backend plus a pool of backends to fall back on). They work
  together but are turned on separately — `modelFailover` works on any tier including the Developer
  default, while the two gateway-level switches need a Premium-class tier.
- **Zones and regions are settings on the existing gateway** → edited into `apim.bicep` rather than
  a new module (they update the same resource, not separate ones).
- **`modelFailover` lives in `llm-api.bicep`** — the chat backend and its fall-back pool are created
  there, and traffic is routed through the pool using the same snippet-injection pattern
  (`FAILOVER_BACKEND` placeholder). Keeping the backends next to the rule that references them gets
  the deployment order right.
- **Put the tier trade-off in plain sight.** Running in multiple regions requires the Premium
  classic tier; the unified doorway and Claude require the v2 tier; you cannot have both in one
  instance today. This is documented in the runbook and caveats as the make-or-break tier decision,
  with a recommendation per priority (resilience first → Premium classic; provider choice first →
  v2).

## Honest constraints
- **Zone spreading and multi-region need a tier change** — the Developer default supports neither,
  so these switches fail on Developer. Added `Premium` to the allowed tiers; documented as a
  requirement (Bicep can't reject a switch/tier mismatch at build time).
- **Token quota counts per region** — `multiRegion` multiplies the effective monthly cap by the
  region count. Cross-referenced to caveats §1; the operator must do the math.
- **Multi-region + network isolation** needs per-region subnet + public IP in each
  `additionalLocations` entry — not auto-derived; flagged validate-before-prod.
- **One OpenAI account means one member in the fall-back pool.** The auto-cutoff for a failing
  backend is the real win within a single region; true run-everywhere-at-once needs a second
  region's backend added to the pool. The pool is built ready for that rather than faking a second
  member.

## Consequences
- `dev` unchanged (all three flags off). `prod`/`regulated` (with a Premium-class SKU) get zone
  redundancy, multi-region, and the breaker-protected pool; `test` gets `modelFailover`.
- `apim.bicep` gains `zones`/`additionalLocations`; `llm-api.bicep` gains the failover backends
  + policy injection; `llm-governance.xml` gains the `FAILOVER_BACKEND` marker (lint still passes).
- Phase 6 (`multiProvider`) adds a second provider backend to the same pool / a v2 sidecar,
  landing the other side of the tier trade-off.
