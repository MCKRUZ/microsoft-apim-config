#!/usr/bin/env sh
# ============================================================================
# lint-policies.sh — structural lint for the APIM policy XML (Phase 2 guardrail)
# ============================================================================
# Runs in CI (validate.yml) and locally before a push. For every file in
# infra/policies/*.xml it asserts:
#   1. the <policies> wrapper and all four sections are present and closed
#   2. every section inherits parent scope via <base /> — this mirrors the
#      Azure Policy "API Management policies should inherit parent scope using
#      <base/>", so a workspace/BU policy can never silently strip a central
#      control (target-architecture §5).
#   3. {{named-value}} tokens are balanced (a stray {{ is a deploy-time failure)
#   4. no hardcoded secret slipped into a policy (keys must come from named values)
#
# IMPORTANT — we do NOT do a strict XML/DOM parse. APIM's policy expression
# language embeds C# with nested double quotes inside attribute values, e.g.
#   counter-key="@(context.Subscription?.Id ?? "anonymous")"
# That is valid APIM but NOT well-formed XML, so xmllint/ElementTree would raise
# false failures. Structural grep/awk checks are the correct tool here.
# ============================================================================
set -eu

POLICY_DIR="${1:-infra/policies}"
SECTIONS="inbound backend outbound on-error"
fail=0

red()   { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; fail=1; }
ok()    { printf '\033[32m✓ %s\033[0m\n' "$1"; }
hdr()   { printf '\n== %s ==\n' "$1"; }

[ -d "$POLICY_DIR" ] || { printf 'policy dir not found: %s\n' "$POLICY_DIR" >&2; exit 1; }

for f in "$POLICY_DIR"/*.xml; do
  [ -e "$f" ] || { printf 'no policy files in %s\n' "$POLICY_DIR" >&2; exit 1; }
  hdr "$(basename "$f")"

  # (1) wrapper
  grep -q '<policies>' "$f"  || red "$f: missing <policies>"
  grep -q '</policies>' "$f" || red "$f: missing </policies>"

  # (1) + (2) each section present, closed, and inheriting via <base/>
  for sec in $SECTIONS; do
    grep -q "<$sec>" "$f"  || { red "$f: missing <$sec>"; continue; }
    grep -q "</$sec>" "$f" || { red "$f: missing </$sec>"; continue; }
    # Extract the section body and confirm a <base /> (or <base/>) inside it.
    if ! awk "/<$sec>/{c=1} c{print} /<\/$sec>/{c=0}" "$f" | grep -Eq '<base ?/>'; then
      red "$f: <$sec> does not inherit parent scope (missing <base />)"
    fi
  done

  # (3) balanced named-value tokens
  open=$(grep -o '{{' "$f" | wc -l | tr -d ' ')
  close=$(grep -o '}}' "$f" | wc -l | tr -d ' ')
  [ "$open" = "$close" ] || red "$f: unbalanced named-value tokens ({{=$open }}=$close)"

  # (4) no hardcoded secrets — keys must arrive via named values / managed identity
  if grep -nEi '(AccountKey=|SharedAccessKey=|sig=[A-Za-z0-9%]{20,}|sk-[A-Za-z0-9]{20,}|password=[^{ "]|Bearer [A-Za-z0-9._-]{20,})' "$f"; then
    red "$f: looks like a hardcoded secret (use a named value / managed identity)"
  fi

  [ "$fail" = 0 ] && ok "$(basename "$f") passed"
done

if [ "$fail" != 0 ]; then
  printf '\n\033[31mpolicy lint FAILED\033[0m\n' >&2
  exit 1
fi
printf '\n\033[32mall policies passed structural lint\033[0m\n'
