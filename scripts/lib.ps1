# ============================================================================
# lib.ps1 — shared helpers for the PowerShell scripts (env discovery + output)
# ============================================================================
# Dot-source from the other *.ps1 scripts: . "$PSScriptRoot/lib.ps1"
# ============================================================================
$ErrorActionPreference = 'Stop'

function Write-Say  { param($m) Write-Host $m -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Warn2{ param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Hdr  { param($m) Write-Host "`n== $m ==" -ForegroundColor White }
function Die        { param($m) Write-Host "[X] $m" -ForegroundColor Red; exit 1 }

function Test-Command { param($n) $null -ne (Get-Command $n -ErrorAction SilentlyContinue) }

# Load deployment outputs into script-scope variables. Prefers azd.
function Get-DeploymentEnv {
    if (-not (Test-Command az)) { Die "Required command not found: az" }
    $env = @{}
    if (Test-Command azd) {
        try {
            azd env get-values 2>$null | ForEach-Object {
                if ($_ -match '^\s*([A-Za-z0-9_]+)="?(.*?)"?\s*$') { $env[$Matches[1]] = $Matches[2] }
            }
        } catch { }
    }
    if (-not $env.ContainsKey('GOVERNED_API_NAME')) { $env['GOVERNED_API_NAME'] = 'azure-openai' }
    if (-not $env['APIM_NAME'] -or -not $env['AZURE_RESOURCE_GROUP']) {
        Die "Could not resolve APIM_NAME / AZURE_RESOURCE_GROUP. Run 'azd env get-values' or set them manually."
    }
    return $env
}
