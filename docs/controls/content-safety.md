# Content Safety (`llm-content-safety`)

GA control. See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it controls

Screens prompts (and optionally completions) through Azure AI Content Safety / Prompt
Shields before they reach the model. For an agent fleet this catches two things humans
can't review at scale: direct jailbreak attempts, and **indirect prompt injection**
hidden inside tool output or RAG content that an agent is about to act on.

## The policy

From `infra/policies/llm-governance.xml` (inbound, before cache lookup):

```xml
<llm-content-safety
    backend-id="content-safety-backend"
    shield-prompt="true"
    enforce-on-completions="true">
    <categories output-type="EightSeverityLevels">
        <category name="Hate"     threshold="4" />
        <category name="Violence" threshold="4" />
        <category name="SelfHarm" threshold="4" />
        <category name="Sexual"   threshold="4" />
    </categories>
</llm-content-safety>
```

- `shield-prompt="true"` — Prompt Shields catches jailbreak **and** indirect injection
  hidden in tool/RAG content.
- Categories Hate / Violence / SelfHarm / Sexual: severity `0–3` passes, `4–7` blocks
  when `threshold="4"`.
- `enforce-on-completions="true"` screens the response too.
- Returns **`403`** when blocked.

## How it's wired in this repo

- Policy: `infra/policies/llm-governance.xml`.
- Azure AI Content Safety resource provisioned in
  `infra/modules/content-safety.bicep`; `disableLocalAuth=true`.
- APIM's system-assigned MI gets **Cognitive Services User** on the account
  (`infra/modules/rbac.bicep`).
- **Known IaC gap:** the content-safety backend's managed-identity auth is **not
  expressible** in the ARM/Bicep backend schema (even `2025-09-01-preview` `credentials`
  has no `managedIdentity` field). So the backend is created **URL-only** in Bicep and MI
  auth is applied post-deploy by `scripts/configure-backend-auth.{sh,ps1}` — or one portal
  toggle: *Backends → content-safety-backend → Authorization credentials → Managed
  identity → System assigned → Resource ID `https://cognitiveservices.azure.com`*.

## How to verify

1. Run `scripts/smoke-test.{sh,ps1}` with a benign prompt → `200`.
2. Send a known jailbreak / disallowed prompt → expect **`403`**.
3. If you get a `401/403` from the backend itself, the MI auth step was skipped — run
   `scripts/configure-backend-auth.{sh,ps1}`.

## Caveats

- **Streaming**: for streamed responses the policy buffers a sliding window and **stops
  forwarding events** on a violation — it does **not** return `403`. Clients must handle a
  truncated stream.
- Tuned for a **limited set of languages**; can misfire on others.
- Requires a **separate Azure AI Content Safety resource**.
- The policy itself works on all tiers (incl. Consumption), but this golden copy requires
  **Developer or v2** because the co-located `llm-token-limit` spend cap is unavailable on
  Consumption — so the full control set never runs there.
