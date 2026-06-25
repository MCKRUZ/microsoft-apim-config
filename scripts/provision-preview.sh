#!/usr/bin/env sh
# ============================================================================
# provision-preview.sh — stand up the PREVIEW agent surfaces + finish GA setup
# ============================================================================
# Run automatically by `azd up` (postprovision hook). Two parts:
#   A. Finish GA core: configure the content-safety backend's managed identity
#      (ARM-schema gap, see configure-backend-auth.sh).
#   B. PREVIEW surfaces: MCP server, A2A agent API, unified model API.
#
# Why guided rather than fully automated for part B: these are preview constructs
# whose management APIs are still changing and lack stable ARM/Bicep types
# (docs/adr/0003). This script attempts each via `az rest` where the path is known
# and always prints the authoritative portal steps + doc link as the reliable path.
# Nothing here is destructive; failures are non-fatal (azd continueOnError=true).
# ============================================================================
. "$(dirname "$0")/lib.sh"
load_env

# ---- Part A: finish the GA content-safety wiring ---------------------------
sh "$(dirname "$0")/configure-backend-auth.sh" || warn "configure-backend-auth reported an issue (see above)."

GW="https://${APIM_NAME}.azure-api.net"

# ---- Part B: PREVIEW surfaces ----------------------------------------------
hdr "PREVIEW: expose a REST API as an MCP server (agent -> tool)"
say "Governs tool traffic. NOTE: policy scope is whole-server, not per-tool."
cat <<STEPS
  Portal: API Management (${APIM_NAME}) -> APIs -> MCP Servers -> + Create
    -> 'Expose an API as an MCP server' -> pick a REST API (import one first if needed)
    -> select operations to expose as tools -> Create
    -> MCP -> Policies: paste infra/policies/mcp-governance.xml
  Endpoint: ${GW}/<api-name>-mcp/mcp
  Docs: https://learn.microsoft.com/azure/api-management/export-rest-mcp-server
STEPS

hdr "PREVIEW: import an A2A agent API (agent -> agent)"
say "Governs agent-to-agent hand-offs (JSON-RPC). Emits OTel gen_ai.agent.id/name."
cat <<STEPS
  Portal: API Management (${APIM_NAME}) -> APIs -> + Add API -> 'A2A Agent'
    -> Agent card URL: <your agent's /.well-known agent card>
    -> set Runtime URL + Agent ID -> Create
    -> A2A -> Policies: paste infra/policies/a2a-governance.xml
  Docs: https://learn.microsoft.com/azure/api-management/agent-to-agent-api
STEPS

hdr "PREVIEW: create the unified model API (one doorway)"
say "Single /llm/v1/chat/completions endpoint; same governance for every backend."
cat <<STEPS
  Portal: API Management (${APIM_NAME}) -> APIs -> Models -> + Add -> 'Unified model API'
    -> API path: /llm/v1
    -> Add model: name 'gpt-4o', format 'OpenAI Chat Completions', URL = your AOAI chat deployment,
       Auth = Managed identity (system-assigned)
    -> reuse the same token-limit / content-safety policies
  Docs: https://learn.microsoft.com/azure/api-management/unified-model-api
STEPS

hdr "PREVIEW: multi-provider — add Claude (Anthropic) [multiProvider flag]"
if [ "${MULTI_PROVIDER_INTENDED:-false}" = "true" ]; then
  say "multiProvider is ON for this environment — follow the steps below."
else
  say "multiProvider is OFF (informational). These are the steps when you turn it on."
fi
say "REQUIRES a v2 tier (Anthropic governance + OpenAI<->Anthropic translation are v2-only)."
say "NOTE: a v2 instance has NO multi-region — multiProvider and multiRegion are exclusive"
say "in one instance (docs/enterprise/target-architecture.md §3). Use a separate v2 instance"
say "or a self-hosted sidecar behind the same edge if you also need multi-region."
KV="${KEY_VAULT_NAME:-<key-vault>}"
cat <<STEPS
  1. Store the Anthropic key in Key Vault (NEVER in a template or named value plaintext):
       az keyvault secret set --vault-name ${KV} --name anthropic-api-key --value <ANTHROPIC_KEY>
  2. Create a Key Vault REFERENCE named value (APIM MI already has Key Vault Secrets User):
       Portal: ${APIM_NAME} -> Named values -> + Add -> Type 'Key vault'
         -> name 'anthropic-api-key' -> select secret '${KV}/anthropic-api-key'
  3. Add the Anthropic backend:
       Portal: ${APIM_NAME} -> Backends -> + Add
         -> URL https://api.anthropic.com -> credentials: header 'x-api-key' = {{anthropic-api-key}}
  4. Add Claude to the unified model API:
       APIs -> Models -> (your unified API) -> + Add model
         -> name 'claude', format 'Anthropic Messages', backend = the Anthropic backend
         -> reuse the SAME token-limit / content-safety policies (governance is provider-agnostic)
  Why the doorway: clients keep calling /llm/v1/chat/completions; APIM translates
  OpenAI <-> Anthropic. Raw cross-provider failover does NOT work without this
  translation (the request/response formats differ).
  Docs: https://learn.microsoft.com/azure/api-management/unified-model-api
STEPS

hdr "Preview provisioning guide complete"
ok "GA core is live and governed. Validate everything with scripts/smoke-test.sh."
