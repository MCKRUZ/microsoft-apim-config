# Unified Model API — "One Doorway"

> **PREVIEW.** Management APIs are unstable and lack stable Bicep types. Provisioned via
> portal/CLI guidance in `scripts/provision-preview.*`, not declarative IaC.

See [architecture](../architecture.md) and [caveats](../caveats.md).
Docs: https://learn.microsoft.com/azure/api-management/unified-model-api

## What it governs

This gives every client one front door for **all** model traffic, using a single request
format (OpenAI's Chat Completions format). Clients write their code against that one format,
and the API gateway (Azure API Management, "APIM") translates it into whatever each model
actually expects. The payoff: agent code no longer has to know or care which provider is
behind the door — the governed entry point stays the same whether the model is Azure OpenAI
or Anthropic (the maker of Claude).

## Endpoint / shape

```
POST /llm/v1/chat/completions     # OpenAI Chat Completions request shape
GET  /models                      # discovery endpoint
```

- The gateway translates the request into the format the backend speaks: **OpenAI Chat
  Completions** or **Anthropic Messages**.
- **Aliases** let clients refer to a model by a friendly name that is separate from the
  real backend deployment name, so the backend can change without breaking client code.
- Supports **failover** — if one backend is down, traffic shifts to another.

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
