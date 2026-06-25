<#
  ============================================================================
  drift-detect.ps1 — fail if live infra/policy has drifted from the repo (Phase 2)
  ============================================================================
  Windows/pwsh twin of drift-detect.sh. Runs `az deployment sub what-if` of the
  repo template against the live subscription; ANY mutating change = drift.

  Exit codes (so CI/automation can branch):
    0  no drift  — live == repo
    2  drift     — live differs (Create/Delete/Modify/Deploy present)
    1  error     — could not evaluate

  Config via params or env: AZURE_LOCATION, GOV_PROFILE, TEMPLATE_FILE, PARAMS_FILE.
  ============================================================================
#>
[CmdletBinding()]
param(
  [string]$Location  = $(if ($env:AZURE_LOCATION) { $env:AZURE_LOCATION } else { 'eastus2' }),
  [string]$Profile   = $(if ($env:GOV_PROFILE)    { $env:GOV_PROFILE }    else { 'dev' }),
  [string]$Template  = $(if ($env:TEMPLATE_FILE)  { $env:TEMPLATE_FILE }  else { 'infra/main.bicep' }),
  [string]$ParamsFile= $(if ($env:PARAMS_FILE)    { $env:PARAMS_FILE }    else { 'infra/main.parameters.json' })
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Error 'az CLI not found'; exit 1 }
if (-not (Test-Path $Template)) { Write-Error "template not found: $Template"; exit 1 }

Write-Host "== what-if: profile=$Profile region=$Location =="

try {
  $json = az deployment sub what-if `
    --location $Location `
    --template-file $Template `
    --parameters "@$ParamsFile" `
    --parameters "profile=$Profile" `
    --no-pretty-print -o json
} catch { Write-Error 'what-if failed (auth or template error)'; exit 1 }

if (-not $json) { Write-Error 'what-if returned no output'; exit 1 }

$data = $json | ConvertFrom-Json
$changes = if ($data.changes) { $data.changes } elseif ($data.properties.changes) { $data.properties.changes } else { @() }
$mutating = @($changes | Where-Object { $_.changeType -in 'Create','Delete','Modify','Deploy' })

if ($mutating.Count -gt 0) {
  Write-Host "DRIFT DETECTED: $($mutating.Count) resource(s) differ from the repo" -ForegroundColor Yellow
  $mutating | ForEach-Object { Write-Host ("  {0,-7} {1}" -f $_.changeType, $_.resourceId) -ForegroundColor Yellow }
  Write-Host 'Reconcile: redeploy the repo (overwrite the drift) or open a PR to adopt the change.' -ForegroundColor Yellow
  exit 2
}

Write-Host 'no drift — live infrastructure matches the repo' -ForegroundColor Green
exit 0
