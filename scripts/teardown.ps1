# ============================================================================
# teardown.ps1 — DESTRUCTIVE: delete the entire resource group
# ============================================================================
# Removes every resource provisioned by this golden copy. Irreversible.
# Prefer `azd down` if you deployed with azd. This is the az-CLI fallback.
# ============================================================================
. "$PSScriptRoot/lib.ps1"
$envv = Get-DeploymentEnv

Write-Hdr "Teardown — DESTRUCTIVE"
Write-Warn2 "This will permanently delete resource group: $($envv['AZURE_RESOURCE_GROUP'])"
Write-Warn2 "(APIM, Azure OpenAI, Redis, Content Safety, Log Analytics, App Insights — all of it.)"
$confirm = Read-Host "Type the resource group name to confirm"
if ($confirm -ne $envv['AZURE_RESOURCE_GROUP']) { Die "Confirmation did not match. Aborted." }

Write-Say "Deleting $($envv['AZURE_RESOURCE_GROUP']) ..."
az group delete --name $envv['AZURE_RESOURCE_GROUP'] --yes --no-wait
Write-Ok "Delete requested (async). Soft-deleted Cognitive Services + APIM may need purging"
Write-Ok "before redeploying with the same names (see docs/runbooks/deploy.md)."
