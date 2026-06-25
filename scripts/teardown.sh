#!/usr/bin/env sh
# ============================================================================
# teardown.sh — DESTRUCTIVE: delete the entire resource group
# ============================================================================
# Removes every resource provisioned by this golden copy. Irreversible.
# Prefer `azd down` if you deployed with azd. This is the az-CLI fallback.
# ============================================================================
. "$(dirname "$0")/lib.sh"
load_env

hdr "Teardown — DESTRUCTIVE"
warn "This will permanently delete resource group: ${AZURE_RESOURCE_GROUP}"
warn "(APIM, Azure OpenAI, Redis, Content Safety, Log Analytics, App Insights — all of it.)"
printf 'Type the resource group name to confirm: '
read -r CONFIRM
[ "$CONFIRM" = "$AZURE_RESOURCE_GROUP" ] || die "Confirmation did not match. Aborted."

say "Deleting ${AZURE_RESOURCE_GROUP} ..."
az group delete --name "$AZURE_RESOURCE_GROUP" --yes --no-wait
ok "Delete requested (running asynchronously). Note: soft-deleted Cognitive Services + APIM"
ok "may need purging before redeploying with the same names (see docs/runbooks/deploy.md)."
