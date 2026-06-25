# ADR-0002 — Developer tier as the default deploy parameter

**Status:** Accepted · **Date:** 2026-06-25

## Context
The APIM SKU drives both cost and capability. A "golden copy" is meant to be cloned and actually run, so the default SKU should let someone stand up the *entire* showcase cheaply, while the docs steer production toward the right tier.

## Decision
Default `apimSkuName` = **Developer**. Document **StandardV2** as the canonical production target. Parameterise the SKU so it's a one-line change.

## Rationale
- Verified against docs: the four GA controls **and** the MCP/A2A/unified-model preview surfaces all support the **Developer** tier. For an OpenAI-only deployment, Developer runs the complete showcase.
- Developer is ~$50/mo vs StandardV2's several-hundred. For a reference/demo that people deploy to learn, that difference matters.
- The only thing Developer can't do that we'd want is **Anthropic** governance (v2-only) — and we're OpenAI-only by design, so it doesn't bite.

## Consequences
- Developer has **no SLA** and ~30–45 min provisioning — fine for a reference, called out in [caveats.md](../caveats.md) so nobody runs production on it.
- Moving to production = set `APIM_SKU=StandardV2` (and mind the per-region token-cap math on multi-region). No code changes.
- Consumption is explicitly disallowed (no token-limit governance).
