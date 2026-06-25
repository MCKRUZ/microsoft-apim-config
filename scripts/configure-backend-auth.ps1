# ============================================================================
# configure-backend-auth.ps1 — set managed-identity auth on the Content Safety backend
# ============================================================================
# WHY THIS SCRIPT EXISTS (known IaC gap): the llm-content-safety policy calls the
# 'content-safety-backend' entity as a black box, so the APIM managed identity must
# be configured ON THE BACKEND ENTITY — which is NOT expressible in the ARM/Bicep
# backend schema (even 2025-09-01-preview). Bicep creates the backend URL-only and
# this script applies the MI auth post-deploy. See docs/caveats.md.
# ============================================================================
. "$PSScriptRoot/lib.ps1"
$envv = Get-DeploymentEnv

Write-Hdr "Configure managed-identity auth on content-safety-backend"

$subId    = az account show --query id -o tsv
$apiVer   = "2024-06-01-preview"
$backendId= "content-safety-backend"
$base     = "https://management.azure.com/subscriptions/$subId/resourceGroups/$($envv['AZURE_RESOURCE_GROUP'])/providers/Microsoft.ApiManagement/service/$($envv['APIM_NAME'])/backends/$backendId"

Write-Say "Reading current backend definition..."
$current = az rest --method get --url "$base`?api-version=$apiVer" 2>$null | ConvertFrom-Json
if (-not $current) { Die "Backend '$backendId' not found — has the infra been deployed?" }
$url = $current.properties.url

Write-Say "Attempting to set credentials -> Managed Identity (resource https://cognitiveservices.azure.com)..."
$body = @{ properties = @{ url = $url; protocol = "http";
  credentials = @{ managedIdentity = @{ resource = "https://cognitiveservices.azure.com" } } } } | ConvertTo-Json -Depth 6

$ok = $false
try {
    az rest --method patch --url "$base`?api-version=$apiVer" --headers "Content-Type=application/json" --body $body 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ok = $true }
} catch { }

if ($ok) {
    Write-Ok "Managed-identity auth applied to $backendId via REST."
} else {
    Write-Warn2 "REST PATCH did not accept a managedIdentity credential on this API version."
    Write-Warn2 "Apply it manually (one toggle) in the portal:"
    @"

  Azure portal -> API Management ($($envv['APIM_NAME'])) -> APIs -> Backends -> $backendId
    -> Authorization credentials -> Managed identity -> Enable
    -> Client identity: System assigned
    -> Resource ID: https://cognitiveservices.azure.com
    -> Save

  (The RBAC role 'Cognitive Services User' is already granted by infra/modules/rbac.bicep.)
"@ | Write-Host
}

Write-Ok "Done. Content-safety screening is active once the backend identity is set."
