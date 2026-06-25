#!/usr/bin/env sh
# ============================================================================
# drift-detect.sh — fail if live infra/policy has drifted from the repo (Phase 2)
# ============================================================================
# Runs `az deployment sub what-if` of the repo template against the live
# subscription and treats ANY non-ignorable change as drift. Used two ways:
#   - scheduled (drift.yml): catch portal edits made out-of-band in prod
#   - on a PR (validate.yml --preview): show the reviewer exactly what will change
#
# Exit codes (so CI can branch):
#   0  no drift  — live == repo
#   2  drift     — live differs from repo (Create/Delete/Modify/Deploy present)
#   1  error     — could not evaluate (auth, bad params, etc.)
#
# Config via env (all have CI-friendly defaults):
#   AZURE_LOCATION      region for the sub-scope what-if           (default eastus2)
#   GOV_PROFILE         capability profile to evaluate against     (default dev)
#   TEMPLATE_FILE       bicep entrypoint                           (default infra/main.bicep)
#   PARAMS_FILE         parameters file                            (default infra/main.parameters.json)
# ============================================================================
set -eu

LOC="${AZURE_LOCATION:-eastus2}"
PROFILE="${GOV_PROFILE:-dev}"
TEMPLATE="${TEMPLATE_FILE:-infra/main.bicep}"
PARAMS="${PARAMS_FILE:-infra/main.parameters.json}"

command -v az >/dev/null 2>&1 || { printf 'az CLI not found\n' >&2; exit 1; }
[ -f "$TEMPLATE" ] || { printf 'template not found: %s\n' "$TEMPLATE" >&2; exit 1; }

printf '== what-if: profile=%s region=%s ==\n' "$PROFILE" "$LOC"

# --no-pretty-print gives machine-readable JSON; we still echo a human view after.
RESULT=$(az deployment sub what-if \
  --location "$LOC" \
  --template-file "$TEMPLATE" \
  --parameters "@$PARAMS" \
  --parameters "profile=$PROFILE" \
  --no-pretty-print -o json) || { printf 'what-if failed (auth or template error)\n' >&2; exit 1; }

# Count changes whose changeType is one that actually mutates the live resource.
# Ignore / NoChange are expected and benign. Uses python3 (present on CI runners).
DRIFTED=$(printf '%s' "$RESULT" | python3 -c '
import sys, json
data = json.load(sys.stdin)
changes = data.get("changes", data.get("properties", {}).get("changes", []))
mut = [c for c in changes if c.get("changeType") in ("Create","Delete","Modify","Deploy")]
for c in mut:
    print(f"  {c.get(\"changeType\"):7} {c.get(\"resourceId\",\"\")}")
sys.stderr.write(str(len(mut)))
' 2>/tmp/drift_count.$$ ) || { printf 'could not parse what-if output\n' >&2; exit 1; }

COUNT=$(cat /tmp/drift_count.$$ 2>/dev/null || echo 0)
rm -f /tmp/drift_count.$$ 2>/dev/null || true

if [ "${COUNT:-0}" -gt 0 ]; then
  printf '\033[33mDRIFT DETECTED: %s resource(s) differ from the repo\033[0m\n' "$COUNT" >&2
  printf '%s\n' "$DRIFTED" >&2
  printf 'Reconcile: redeploy the repo (overwrite the drift) or open a PR to adopt the change.\n' >&2
  exit 2
fi

printf '\033[32mno drift — live infrastructure matches the repo\033[0m\n'
exit 0
