# ADR-0002 — Developer tier as the default deploy parameter

**Status:** Accepted · **Date:** 2026-06-25

## Context
The pricing tier you pick for the API gateway (Azure API Management, "APIM") controls both how much it costs and what it can do. This project is a "golden copy" — a reference build meant to be copied and actually run by others to learn from. So the out-of-the-box tier should let someone stand up the *entire* showcase cheaply, while the docs point toward the right tier for real production use.

## Decision
Default the gateway tier (`apimSkuName`) to **Developer**. Document **StandardV2** as the recommended production tier. Make the tier a single setting so switching is a one-line change.

## Rationale
- Confirmed against the documentation: the four production-ready ("GA", generally available) controls **and** the not-yet-final ("preview") features — tool serving (MCP), agent-to-agent (A2A), and the one-endpoint model API — all run on the **Developer** tier. For an OpenAI-only deployment, Developer runs the complete showcase.
- Developer costs about $50/month versus several hundred for StandardV2. For a reference build that people deploy just to learn, that gap matters.
- The only thing Developer can't do that we'd want is governing Anthropic's Claude (which needs the v2 tier) — and we're OpenAI-only by design, so it doesn't bite.

## Consequences
- Developer carries **no uptime guarantee** (no SLA) and takes about 30–45 minutes to spin up — fine for a reference build, and called out in [caveats.md](../caveats.md) so nobody runs production on it.
- Moving to production is just setting `APIM_SKU=StandardV2` (and, if running in multiple regions, redoing the per-region usage-cap math). No code changes.
- The cheapest "Consumption" tier is explicitly disallowed because it can't cap AI usage.
