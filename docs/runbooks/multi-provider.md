# Runbook — multi-provider (Phase 6)

One doorway, many models. Clients call a single `/llm/v1/chat/completions`; the gateway
governs and routes to OpenAI, Anthropic (Claude), or Google — translating formats so the
client never changes. Flags: `multiProvider` (the doorway/Claude, **preview, v2-only**) and
`useKeyVault` (store the non-Azure provider's API key in Azure Key Vault — Azure's production-ready secrets locker — instead of anywhere in the deployment templates).

## The honest split (why part of this is a script)

| Piece | Maturity | Delivered as |
|---|---|---|
| **Key Vault + APIM MI access** (`useKeyVault`) | GA | Bicep — `modules/keyvault.bicep` |
| **Unified doorway + Claude governance** (`multiProvider`) | **Preview, v2-only** | `scripts/provision-preview.*` + this runbook |

The unified model API and Anthropic Messages governance lack stable ARM/Bicep types and
need an out-of-band API key — same profile as the other preview surfaces (MCP/A2A), so they
ship as a guided script ([ADR-0003](../adr/0003-preview-via-scripts.md)), not faked Bicep.
`multiProvider` is therefore informational at the Bicep layer (it sets the
`MULTI_PROVIDER_INTENDED` output the script reads), like `pipelineGuardrails`.

## ⚠ The tier trade-off (the load-bearing constraint)

> **Multi-provider (v2-only) and multi-region (Premium classic only) cannot coexist in one
> instance today.** ([target-architecture §3](../enterprise/target-architecture.md#3-tier-decision-the-load-bearing-choice))

If you need both, run them as **separate instances behind the same edge**:
- a **Premium classic** instance for multi-region OpenAI (Phase 5), and
- a **v2** instance (or a **self-hosted gateway sidecar**) for the multi-provider doorway.

A v2 instance has no multi-region; a Premium-classic instance can't do the v2 unified doorway.
This is a current Azure limit — revisit when v2 ships multi-region.

## Secret handling (`useKeyVault`)

The golden copy is keyless to Azure (APIM MI calls OpenAI/Content Safety). A non-Azure
provider key is the **first real secret**, and Key Vault is its home:

1. Deploy with `useKeyVault` on (test/prod/regulated default it). `modules/keyvault.bicep`
   creates the vault and grants APIM's MI **Key Vault Secrets User**.
2. Store the key (out-of-band — never in a template):
   ```bash
   az keyvault secret set --vault-name <KEY_VAULT_NAME> --name anthropic-api-key --value <key>
   ```
3. Create a **Key Vault reference** named value `anthropic-api-key` → APIM resolves it at
   runtime and rotates without redeploy. The plaintext never touches a template, output, or
   named-value body.

> Ordering gotcha: APIM validates a KV-reference named value when it's created, so the secret
> must exist **first**. That's why the named value is created post-deploy (script), not in Bicep.

## Adding Claude — the guided flow

`provision-preview.*` (run by `azd up`, or manually) prints the steps, parameterized with your
Key Vault + APIM names. Summary:

1. Store the Anthropic key in Key Vault (above).
2. Named value `anthropic-api-key` → the KV secret.
3. Backend `https://api.anthropic.com`, credential header `x-api-key = {{anthropic-api-key}}`.
4. Unified model API → add model `claude`, format **Anthropic Messages**, backend = the
   Anthropic backend. **Reuse the same token-limit / content-safety policies** — governance is
   provider-agnostic; that's the whole point of the doorway.

## Why you can't just pool OpenAI + Claude for failover

The Phase-5 `openai-pool` load-balances across backends that speak the **same** wire format.
OpenAI and Anthropic Messages differ, so a raw pool failover would send OpenAI-shaped requests
to Anthropic and fail. Cross-provider failover **requires the unified doorway's translation** —
which is the v2-only preview piece. So: same-provider failover = Phase 5 (GA pool); cross-
provider = Phase 6 (preview doorway). Don't mix them in one pool.

## Verify
- `useKeyVault`: Key Vault exists; APIM MI has **Key Vault Secrets User** (Access control → role
  assignments).
- After the guided steps: `GET /llm/v1/models` lists both `gpt-4o` and `claude`; a call to
  `/llm/v1/chat/completions` with `model: claude` is governed (token-limit + content-safety fire)
  and translated. Confirm token metrics carry the model dimension.
