# ADR-0001 — Azure API Management as the governance gateway

**Status:** Accepted · **Date:** 2026-06-25

## Context
We need one place where all AI traffic is controlled — a single checkpoint that every call passes through so spend caps, identity, content safety, and audit logging are enforced in one spot. "All AI traffic" means three things: calls to the AI models, calls to tools the agents use, and hand-offs between agents (agent-to-agent, "A2A"). The candidates we weighed: the API gateway (Azure API Management, "APIM"), Kong, an AWS Bedrock plus separate gateway combo, or smaller players (Gravitee, Tyk, Truefoundry).

## Decision
Use **Azure API Management** as that single checkpoint.

## Rationale
- The organisation is already all-in on Azure (Azure, .NET, and Azure's deployment templates, Bicep/ARM). For such an org, APIM's AI controls come **built in** and feed the monitoring tools already in use (Azure Monitor / App Insights) — nothing extra to stitch together.
- APIM is the one gateway that sits in front of **all three** kinds of traffic — model calls, tool calls (the tools agents use, exposed through the "MCP" tool protocol), and agent-to-agent hand-offs — under a single control point and a single set of rules.
- Its core feature set is already generally available / production-ready ("GA") today: token limits (caps on AI usage), content safety, a cache for repeated questions, and cost tracking per team.

## Honest limits (why this isn't an unqualified win)
- A few things don't come for free: governing Anthropic's Claude requires the newer v2 tier; company-wide budgets require some per-region arithmetic; the cheapest "Consumption" tier can't enforce spend controls at all; and tool governance covers a whole tool server at once, not each individual tool. Whether APIM is the single *most complete* option is genuinely debated among vendors.
- These are acceptable because (a) we are OpenAI-only and Azure-committed, and (b) the limits are documented in [caveats.md](../caveats.md), not hidden.

## Consequences
- We inherit APIM's tiers, quotas, and provisioning times.
- A non-Azure org, or one standardised on Claude as primary, should re-evaluate — the conclusion is specific to the Azure-committed context.
