# Runbook — multi-provider (Phase 6)

One doorway, many models. Clients call a single `/llm/v1/chat/completions`; the gateway
governs and routes to OpenAI, Anthropic (Claude), or Google — translating formats so the
client never changes. Flags: `multiProvider` (the doorway/Claude, **preview, v2-only**) and
`useKeyVault` (store the non-Azure provider's API key in Azure Key Vault — Azure's production-ready secrets locker — instead of anywhere in the deployment templates).

## The honest split (why part of this is a script)

| Piece | Maturity | Delivered as |
|---|---|---|
| **Key Vault + APIM MI access** (`useKeyVault`) | GA (production-ready) | Bicep — `modules/keyvault.bicep` |
| **Unified doorway + Claude governance** (`multiProvider`) | **Preview (not yet final), v2-only** | `scripts/provision-preview.*` + this runbook |

The unified model API and the Anthropic Messages governance don't yet have stable Bicep/ARM
definitions, and they need an API key supplied separately — the same situation as the other preview features (the standard agents use to reach tools, MCP, and agent-to-agent, A2A) — so they
ship as a guided script ([ADR-0003](../adr/0003-preview-via-scripts.md)) rather than fake Bicep.
At the Bicep layer, `multiProvider` is therefore just informational (it sets the
`MULTI_PROVIDER_INTENDED` output that the script reads), the same way `pipelineGuardrails` is.

## ⚠ The tier trade-off (the load-bearing constraint)

> **Multi-provider (v2-only) and multi-region (Premium classic only) cannot run in the same
> instance today.** ([target-architecture §3](../enterprise/target-architecture.md#3-tier-decision-the-load-bearing-choice))

If you need both, run them as **two separate instances behind the same front door**:
- a **Premium classic** instance for multi-region OpenAI (Phase 5), and
- a **v2** instance (or a **self-hosted companion gateway, a "sidecar"**) for the multi-provider doorway.

A v2 instance can't do multi-region; a Premium-classic instance can't do the v2 unified doorway.
This is a current Azure limitation — revisit it when v2 adds multi-region.

## Secret handling (`useKeyVault`)

The standard configuration uses no stored keys for Azure services (the gateway reaches OpenAI and Content Safety with its own Azure-issued identity). A non-Azure
provider key is the **first real secret** in the system, and Key Vault (Azure's secrets locker) is where it belongs:

1. Deploy with `useKeyVault` on (the test/prod/regulated profiles default it on). `modules/keyvault.bicep`
   creates the vault and grants the gateway's identity the **Key Vault Secrets User** role.
2. Store the key (separately — never inside a template):
   ```bash
   az keyvault secret set --vault-name <KEY_VAULT_NAME> --name anthropic-api-key --value <key>
   ```
3. Create a named value `anthropic-api-key` that **points at the Key Vault secret** → the gateway looks it up at
   request time and picks up rotations without a redeploy. The plaintext key never appears in a template, an
   output, or the named-value itself.

> Ordering gotcha: the gateway checks a Key Vault-linked named value the moment it's created, so the secret
> must already exist **first**. That's why this named value is created after the deploy (by the script), not in Bicep.

## Adding Claude — the guided flow

`provision-preview.*` (run by `azd up`, or by hand) prints the steps, filled in with your
Key Vault and gateway names. In summary:

1. Store the Anthropic key in Key Vault (above).
2. Point the named value `anthropic-api-key` at that Key Vault secret.
3. Add a backend `https://api.anthropic.com` with the credential header `x-api-key = {{anthropic-api-key}}`.
4. In the unified model API, add a model `claude` with format **Anthropic Messages** and the
   Anthropic backend. **Reuse the same token-limit and content-safety policies** — governance doesn't care which
   provider it's protecting, which is the whole point of the single doorway.

## Why you can't just pool OpenAI + Claude for failover

The Phase-5 `openai-pool` load-balances across backends that all speak the **same** request format.
OpenAI and Anthropic Messages use different formats, so a plain pool failover would send OpenAI-shaped requests
to Anthropic and fail. Failing over across providers **requires the unified doorway to translate between formats** —
which is the v2-only preview piece. So: same-provider failover = Phase 5 (the production-ready pool); cross-
provider failover = Phase 6 (the preview doorway). Don't mix the two in one pool.

## Verify
- `useKeyVault`: the Key Vault exists, and the gateway's identity has the **Key Vault Secrets User** role (Access control → role
  assignments).
- After the guided steps: `GET /llm/v1/models` lists both `gpt-4o` and `claude`; a call to
  `/llm/v1/chat/completions` with `model: claude` is governed (the token-limit and content-safety controls fire)
  and translated. Confirm the token metrics include the model name as a dimension.
