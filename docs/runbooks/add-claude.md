# Runbook: Add Claude (Multi-Provider)

Add Anthropic Claude as a second model backend behind the same gateway. The showcase
ships **Azure OpenAI only**; this is the multi-provider path.

See [unified-doorway](../controls/unified-doorway.md) and [caveats](../caveats.md).

## Hard requirement: StandardV2 tier

Anthropic **token-limit and semantic-cache support is v2-only**. The default Developer
tier cannot govern Anthropic traffic with the GA controls. You must be on **StandardV2**
(the production target) before adding Claude. Plan a tier move first.

## Steps

1. **Move to StandardV2** if not already there.

2. **Add a backend with API format `Anthropic Messages`.**

3. Wire it one of two ways:

   - **Preferred — unified model API.** Add the Anthropic backend to the existing
     `/llm/v1/chat/completions` doorway and create an **alias** for the Claude model.
     Clients keep sending OpenAI Chat Completions shape; APIM translates to Anthropic
     Messages. Supports failover across backends.
   - **Alternative — a second LLM API.** Stand up a separate Anthropic-backed API in
     APIM.

4. **Apply the same four GA policies** — the governance contract is identical:
   [token-limits](../controls/token-limits.md),
   [cost-attribution](../controls/cost-attribution.md),
   [content-safety](../controls/content-safety.md),
   [semantic-cache](../controls/semantic-cache.md).

## Caveats

- **v2-only**: token-limit / cache governance for Anthropic does not exist on Developer
  or Consumption tiers.
- Backend MI auth still follows the
  [content-safety](../controls/content-safety.md) post-deploy pattern where applicable.
- Prefer the unified doorway so agent code stays on the single OpenAI-shaped contract and
  the provider switch is an alias + backend change, not a client change.

## Verify

`GET /models` lists the new Claude alias; `POST /llm/v1/chat/completions` targeting that
alias returns a translated completion, and the four controls (quota, metrics, safety,
cache) apply to it.
