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
Write-Say "OpenAI-only here. Adding Claude = backend-add (Anthropic Messages) + StandardV2 tier."
@"
  Portal: API Management ($($envv['APIM_NAME'])) -> APIs -> Models -> + Add -> 'Unified model API'
    -> API path: /llm/v1
    -> Add model: name 'gpt-4o', format 'OpenAI Chat Completions', URL = your AOAI chat deployment,
       Auth = Managed identity (system-assigned)
    -> reuse the same token-limit / content-safety policies
  Docs: https://learn.microsoft.com/azure/api-management/unified-model-api
"@ | Write-Host

Write-Hdr "Preview provisioning guide complete"
Write-Ok "GA core is live and governed. Validate everything with scripts/smoke-test.ps1."
