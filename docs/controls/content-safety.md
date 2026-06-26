# Content Safety (`llm-content-safety`)

GA control. See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it controls

This is the safety screen. It checks the text going into the model (and, optionally, the
model's reply) through Azure AI Content Safety and the jailbreak / prompt-injection
detector (Prompt Shields) before that text reaches the model. For a fleet of AI agents it
catches two things no human team could review at the same volume: direct jailbreak attempts
(tricking the model into ignoring its rules), and **indirect prompt injection** — malicious
instructions hidden inside tool output or retrieved documents (RAG content) that an agent is
about to act on.

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
- The API gateway (Azure API Management, "APIM") signs in to the safety service using its
  own Azure-issued identity (a managed identity — no stored password), which is granted the
  **Cognitive Services User** role on the account (`infra/modules/rbac.bicep`).
- **Known infrastructure-as-code gap:** Azure's deployment templates (ARM/Bicep) cannot
  express this managed-identity sign-in for the safety backend — even the newest schema
  (`2025-09-01-preview` `credentials`) has no `managedIdentity` field. So the backend is
  created **URL-only** in Bicep, and the sign-in is wired up after deployment by
  `scripts/configure-backend-auth.{sh,ps1}` — or by one portal toggle: *Backends →
  content-safety-backend → Authorization credentials → Managed identity → System assigned →
  Resource ID `https://cognitiveservices.azure.com`*.

## How to verify

1. Run `scripts/smoke-test.{sh,ps1}` with a benign prompt → `200`.
2. Send a known jailbreak / disallowed prompt → expect **`403`**.
3. If you get a `401/403` from the backend itself, the post-deploy sign-in step was skipped
   — run `scripts/configure-backend-auth.{sh,ps1}`.

## Caveats

- **Streaming**: for streamed responses the policy buffers a sliding window and **stops
  forwarding events** on a violation — it does **not** return `403`. Clients must handle a
  truncated stream.
- Tuned for a **limited set of languages**; can misfire on others.
- Requires a **separate Azure AI Content Safety resource**.
- The policy itself works on all tiers (incl. Consumption), but this golden copy requires
  **Developer or v2** because the co-located `llm-token-limit` spend cap is unavailable on
  Consumption — so the full control set never runs there.
