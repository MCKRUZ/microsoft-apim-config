<#
  ============================================================================
  lint-policies.ps1 — structural lint for the APIM policy XML (Phase 2 guardrail)
  ============================================================================
  Windows/pwsh twin of lint-policies.sh. Same assertions per infra/policies/*.xml:
    1. <policies> wrapper + all four sections present and closed
    2. every section inherits parent scope via <base /> (mirrors the Azure Policy
       "policies should inherit parent scope using <base/>" — a BU cannot strip a
       central control)
    3. {{named-value}} tokens balanced
    4. no hardcoded secrets

  We deliberately do NOT use [xml] / DOM parsing: APIM expressions embed C# with
  nested double quotes inside attribute values (e.g.
  counter-key="@(context.Subscription?.Id ?? "anonymous")"), which is valid APIM
  but not well-formed XML — a DOM parse would raise false failures.
  ============================================================================
#>
[CmdletBinding()]
param([string]$PolicyDir = "infra/policies")

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Red($m) { Write-Host "✗ $m" -ForegroundColor Red;   $script:fail = $true }
function Ok($m)  { Write-Host "✓ $m" -ForegroundColor Green }
function Hdr($m) { Write-Host "`n== $m ==" }

if (-not (Test-Path $PolicyDir)) { throw "policy dir not found: $PolicyDir" }
$files = Get-ChildItem -Path $PolicyDir -Filter *.xml
if (-not $files) { throw "no policy files in $PolicyDir" }

$sections = 'inbound','backend','outbound','on-error'

foreach ($f in $files) {
  Hdr $f.Name
  $text = Get-Content -Raw -LiteralPath $f.FullName

  if ($text -notmatch '<policies>')  { Red "$($f.Name): missing <policies>" }
  if ($text -notmatch '</policies>') { Red "$($f.Name): missing </policies>" }

  foreach ($sec in $sections) {
    if ($text -notmatch "<$sec>")  { Red "$($f.Name): missing <$sec>";  continue }
    if ($text -notmatch "</$sec>") { Red "$($f.Name): missing </$sec>"; continue }
    # Body between the section tags must contain a <base /> for scope inheritance.
    $m = [regex]::Match($text, "<$sec>(?<body>.*?)</$sec>", 'Singleline')
    if (-not ($m.Groups['body'].Value -match '<base ?/>')) {
      Red "$($f.Name): <$sec> does not inherit parent scope (missing <base />)"
    }
  }

  $open  = ([regex]::Matches($text, '\{\{')).Count
  $close = ([regex]::Matches($text, '\}\}')).Count
  if ($open -ne $close) { Red "$($f.Name): unbalanced named-value tokens ({{=$open }}=$close)" }

  if ($text -match '(?i)(AccountKey=|SharedAccessKey=|sig=[A-Za-z0-9%]{20,}|sk-[A-Za-z0-9]{20,}|password=[^{ "]|Bearer [A-Za-z0-9._-]{20,})') {
    Red "$($f.Name): looks like a hardcoded secret (use a named value / managed identity)"
  }

  if (-not $script:fail) { Ok "$($f.Name) passed" }
}

if ($script:fail) { Write-Host "`npolicy lint FAILED" -ForegroundColor Red; exit 1 }
Write-Host "`nall policies passed structural lint" -ForegroundColor Green
