# ============================================================================
# provision-preview.ps1 — stand up the PREVIEW agent surfaces + finish GA setup
# ============================================================================
# Run automatically by `azd up` (postprovision hook). Two parts:
#   A. Finish GA core: configure the content-safety backend's managed identity.
#   B. PREVIEW surfaces: MCP server, A2A agent API, unified model API (guided —
#      preview management APIs are unstable / lack ARM types; see docs/adr/0003).
# Nothing here is destructive; failures are non-fatal.
# ============================================================================
. "$PSScriptRoot/lib.ps1"
$envv = Get-DeploymentEnv

# ---- Part A: finish the GA content-safety wiring ---------------------------
try { & "$PSScriptRoot/configure-backend-auth.ps1" } catch { Write-Warn2 "configure-backend-auth reported an issue (see above)." }

$gw = "https://$($envv['APIM_NAME']).azure-api.net"

# ---- Part B: PREVIEW surfaces ----------------------------------------------
Write-Hdr "PREVIEW: expose a REST API as an MCP server (agent -> tool)"
Write-Say "Governs tool traffic. NOTE: policy scope is whole-server, not per-tool."
@"
  Portal: API Management ($($envv['APIM_NAME'])) -> APIs -> MCP Servers -> + Create
    -> 'Expose an API as an MCP server' -> pick a REST API (import one first if needed)
    -> select operations to expose as tools -> Create
    -> MCP -> Policies: paste infra/policies/mcp-governance.xml
  Endpoint: $gw/<api-name>-mcp/mcp
  Docs: https://learn.microsoft.com/azure/api-management/export-rest-mcp-server
"@ | Write-Host

Write-Hdr "PREVIEW: import an A2A agent API (agent -> agent)"
Write-Say "Governs agent-to-agent hand-offs (JSON-RPC). Emits OTel gen_ai.agent.id/name."
@"
  Portal: API Management ($($envv['APIM_NAME'])) -> APIs -> + Add API -> 'A2A Agent'
    -> Agent card URL: <your agent's /.well-known agent card>
    -> set Runtime URL + Agent ID -> Create
    -> A2A -> Policies: paste infra/policies/a2a-governance.xml
  Docs: https://learn.microsoft.com/azure/api-management/agent-to-agent-api
"@ | Write-Host

Write-Hdr "PREVIEW: create the unified model API (one doorway)"
Write-Say "Single /llm/v1/chat/completions endpoint; same governance for every backend."
@"
  Portal: API Management ($($envv['APIM_NAME'])) -> APIs -> Models -> + Add -> 'Unified model API'
    -> API path: /llm/v1
    -> Add model: name 'gpt-4o', format 'OpenAI Chat Completions', URL = your AOAI chat deployment,
       Auth = Managed identity (system-assigned)
    -> reuse the same token-limit / content-safety policies
  Docs: https://learn.microsoft.com/azure/api-management/unified-model-api
"@ | Write-Host

Write-Hdr "PREVIEW: multi-provider — add Claude (Anthropic) [multiProvider flag]"
if ($envv['MULTI_PROVIDER_INTENDED'] -eq 'true') {
  Write-Say "multiProvider is ON for this environment — follow the steps below."
} else {
  Write-Say "multiProvider is OFF (informational). These are the steps when you turn it on."
}
Write-Say "REQUIRES a v2 tier (Anthropic governance + OpenAI<->Anthropic translation are v2-only)."
Write-Say "NOTE: a v2 instance has NO multi-region — multiProvider and multiRegion are exclusive in"
Write-Say "one instance (target-architecture.md S3). Use a separate v2 instance or self-hosted sidecar."
$kv = if ($envv['KEY_VAULT_NAME']) { $envv['KEY_VAULT_NAME'] } else { '<key-vault>' }
@"
  1. Store the Anthropic key in Key Vault (NEVER in a template or named value plaintext):
       az keyvault secret set --vault-name $kv --name anthropic-api-key --value <ANTHROPIC_KEY>
  2. Create a Key Vault REFERENCE named value (APIM MI already has Key Vault Secrets User):
       Portal: $($envv['APIM_NAME']) -> Named values -> + Add -> Type 'Key vault'
         -> name 'anthropic-api-key' -> select secret '$kv/anthropic-api-key'
  3. Add the Anthropic backend:
       Portal: $($envv['APIM_NAME']) -> Backends -> + Add
         -> URL https://api.anthropic.com -> credentials: header 'x-api-key' = {{anthropic-api-key}}
  4. Add Claude to the unified model API:
       APIs -> Models -> (your unified API) -> + Add model
         -> name 'claude', format 'Anthropic Messages', backend = the Anthropic backend
         -> reuse the SAME token-limit / content-safety policies (governance is provider-agnostic)
  Why the doorway: clients keep calling /llm/v1/chat/completions; APIM translates
  OpenAI <-> Anthropic. Raw cross-provider failover does NOT work without this
  translation (the request/response formats differ).
  Docs: https://learn.microsoft.com/azure/api-management/unified-model-api
"@ | Write-Host

Write-Hdr "Preview provisioning guide complete"
Write-Ok "GA core is live and governed. Validate everything with scripts/smoke-test.ps1."
