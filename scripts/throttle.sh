#!/usr/bin/env sh
# ============================================================================
# throttle.sh — the auto-throttle actuator (Phase 3 SecOps loop)
# ============================================================================
# Lowers (or restores) the tokens-per-minute named value the governance policy
# reads, so a budget breach can be answered with enforcement, not just an email.
# The budget alert (modules/secops.bicep) fires → action group → this script runs
# (manually, or via an Automation runbook / Logic App wired to the action group's
# webhook — see docs/runbooks/secops-loop.md).
#
# Updating the named value takes effect on subsequent requests with no redeploy;
# the same policy keeps serving every team at the new cap.
#
# Usage:
#   throttle.sh <tokens-per-minute>     e.g. throttle.sh 100   (clamp hard)
#   throttle.sh restore <value>         e.g. throttle.sh restore 1000
# ============================================================================
. "$(dirname "$0")/lib.sh"
load_env

NV_ID="tokens-per-minute"

if [ "${1:-}" = "restore" ]; then
  VALUE="${2:?restore needs a value, e.g. throttle.sh restore 1000}"
  ACTION="restore"
else
  VALUE="${1:-100}"
  ACTION="throttle"
fi

case "$VALUE" in
  ''|*[!0-9]*) die "Value must be a positive integer (tokens per minute). Got: '$VALUE'" ;;
esac

hdr "${ACTION}: set ${NV_ID} = ${VALUE} on ${APIM_NAME}"
az apim nv update \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --service-name "$APIM_NAME" \
  --named-value-id "$NV_ID" \
  --value "$VALUE" >/dev/null \
  || die "Failed to update named value ${NV_ID}."

ok "${NV_ID} is now ${VALUE} TPM — effective on the next requests."
warn "This diverges live config from the repo. drift-detect.* will flag it until you redeploy or adopt the change."
