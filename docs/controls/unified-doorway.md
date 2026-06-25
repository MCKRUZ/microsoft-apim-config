# Unified Model API — "One Doorway"

> **PREVIEW.** Management APIs are unstable and lack stable Bicep types. Provisioned via
> portal/CLI guidance in `scripts/provision-preview.*`, not declarative IaC.

See [architecture](../architecture.md) and [caveats](../caveats.md).
Docs: https://learn.microsoft.com/azure/api-management/unified-model-api

## What it governs

A single client endpoint for **all** model traffic, in OpenAI Chat Completions format.
Clients code against one contract; APIM translates to whatever backend format each model
speaks. This decouples agent code from provider choice — the governed surface stays the
same whether the backend is Azure OpenAI or Anthropic.

## Endpoint / shape

```
POST /llm/v1/chat/completions     # OpenAI Chat Completions request shape
GET  /models                      # discovery endpoint
```

- APIM translates the request to the backend format: **OpenAI Chat Completions** or
  **Anthropic Messages**.
- **Aliases** decouple client-facing model names from backend deployment names.
- Supports **failover** across backends.

In this repo it points at **Azure OpenAI only**.

## How to provision

1. Run `scripts/provision-preview.{sh,ps1}` — sets up the unified API (no stable Bicep
   type yet).
2. Or follow the portal/CLI steps in the Microsoft Learn doc linked above.

## Governance

The same four GA controls apply at this API scope —
[token-limits](./token-limits.md), [cost-attribution](./cost-attribution.md),
[content-safety](./content-safety.md), [semantic-cache](./semantic-cache.md).

## Limitations / caveats

- Adding Claude = add a backend with format **Anthropic Messages**, and it **requires
  StandardV2 tier** — Anthropic token-limit/cache support is **v2-only**. See
  [runbooks/add-claude](../runbooks/add-claude.md).
- Preview: API shape and management surface may change.

## Test

`GET /models` should list the configured aliases; `POST /llm/v1/chat/completions` with a
team key should return an OpenAI-shaped completion from the Azure OpenAI backend.
