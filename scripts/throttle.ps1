<#
  ============================================================================
  throttle.ps1 — the auto-throttle actuator (Phase 3 SecOps loop)
  ============================================================================
  Windows/pwsh twin of throttle.sh. Lowers (or restores) the tokens-per-minute
  named value the governance policy reads, so a budget breach is answered with
  enforcement, not just an email. Wire to the SecOps action group via an
  Automation runbook / Logic App (see docs/runbooks/secops-loop.md), or run by hand.

  Usage:
    throttle.ps1 -Value 100                 # clamp hard
    throttle.ps1 -Restore -Value 1000       # restore
  ============================================================================
#>
[CmdletBinding()]
param(
  [int]$Value = 100,
  [switch]$Restore
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/lib.ps1"
$d = Get-DeploymentEnv   # hashtable: APIM_NAME / AZURE_RESOURCE_GROUP (azd or ARM outputs)

if ($Value -le 0) { Die "Value must be a positive integer (tokens per minute). Got: $Value" }
$action = if ($Restore) { 'restore' } else { 'throttle' }

Write-Hdr "${action}: set tokens-per-minute = $Value on $($d['APIM_NAME'])"
az apim nv update `
  --resource-group $d['AZURE_RESOURCE_GROUP'] `
  --service-name $d['APIM_NAME'] `
  --named-value-id 'tokens-per-minute' `
  --value $Value | Out-Null
if ($LASTEXITCODE -ne 0) { Die 'Failed to update named value tokens-per-minute.' }

Write-Ok "tokens-per-minute is now $Value TPM — effective on the next requests."
Write-Warn2 "This diverges live config from the repo. drift-detect.* will flag it until you redeploy or adopt the change."
