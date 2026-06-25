# ADR-0001 — Azure API Management as the governance gateway

**Status:** Accepted · **Date:** 2026-06-25

## Context
We need a single enforcement point for AI agent traffic — model calls, tool calls, and agent-to-agent hand-offs — where spend caps, identity, content safety, and audit live. The candidates: Azure API Management, Kong, an AWS Bedrock + separate gateway combo, or smaller players (Gravitee, Tyk, Truefoundry).

## Decision
Use **Azure API Management**.

## Rationale
- The organisation is Azure-committed (Azure/.NET/Bicep stack). For an Azure-committed org, APIM's AI controls are **built in** and feed the same Azure Monitor / App Insights tooling already in use — nothing extra to stitch together.
- APIM is the one gateway that sits in front of **all three** traffic surfaces (model, MCP tool, A2A) with one control plane and one set of policies.
- The GA core (token limits, content safety, semantic cache, cost attribution) is production-ready today.

## Honest limits (why this isn't an unqualified win)
- Governing Claude needs a v2 tier; company-wide budgets need per-region math; the Consumption tier is excluded from spend controls; MCP tool governance is whole-server, not per-tool. The claim that APIM is the single *most complete* option is genuinely contested across vendors.
- These are acceptable because (a) we are OpenAI-only and Azure-committed, and (b) the limits are documented in [caveats.md](../caveats.md), not hidden.

## Consequences
- We inherit APIM's tiers, quotas, and provisioning times.
- A non-Azure org, or one standardised on Claude as primary, should re-evaluate — the conclusion is specific to the Azure-committed context.
