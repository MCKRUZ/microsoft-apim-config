#!/usr/bin/env sh
# ============================================================================
# configure-backend-auth.sh — set managed-identity auth on the Content Safety backend
# ============================================================================
# WHY THIS SCRIPT EXISTS (known IaC gap, verified against docs):
#   The llm-content-safety policy calls the 'content-safety-backend' entity as a
#   black box, so the APIM managed identity must be configured ON THE BACKEND ENTITY.
#   That is NOT expressible in the ARM/Bicep backend schema (even 2025-09-01-preview
#   'credentials' has no managedIdentity field). So Bicep creates the backend URL-only
#   and this script applies the MI auth post-deploy.
#
# It attempts the REST PATCH; if your API version rejects it, the reliable fallback
# is the one-toggle portal step printed at the end. See docs/caveats.md.
# ============================================================================
. "$(dirname "$0")/lib.sh"
load_env

hdr "Configure managed-identity auth on content-safety-backend"

SUB_ID=$(az account show --query id -o tsv)
API_VER="2024-06-01-preview"
BACKEND_ID="content-safety-backend"
BASE="https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/backends/${BACKEND_ID}"

say "Reading current backend definition..."
CURRENT=$(az rest --method get --url "${BASE}?api-version=${API_VER}" 2>/dev/null) || die "Backend '${BACKEND_ID}' not found — has the infra been deployed?"
URL=$(printf '%s' "$CURRENT" | az rest --method get --url "${BASE}?api-version=${API_VER}" --query 'properties.url' -o tsv 2>/dev/null)

say "Attempting to set credentials -> Managed Identity (resource https://cognitiveservices.azure.com)..."
BODY=$(cat <<JSON
{ "properties": { "url": "${URL}", "protocol": "http",
  "credentials": { "managedIdentity": { "resource": "https://cognitiveservices.azure.com" } } } }
JSON
)
if az rest --method patch --url "${BASE}?api-version=${API_VER}" \
     --headers "Content-Type=application/json" --body "$BODY" >/dev/null 2>&1; then
  ok "Managed-identity auth applied to ${BACKEND_ID} via REST."
else
  warn "REST PATCH did not accept a managedIdentity credential on this API version."
  warn "Apply it manually (one toggle) in the portal:"
  cat <<STEPS

  Azure portal -> API Management (${APIM_NAME}) -> APIs -> Backends -> ${BACKEND_ID}
    -> Authorization credentials -> Managed identity -> Enable
    -> Client identity: System assigned
    -> Resource ID: https://cognitiveservices.azure.com
    -> Save

  (The RBAC role 'Cognitive Services User' is already granted by infra/modules/rbac.bicep.)
STEPS
fi

ok "Done. Content-safety screening is active once the backend identity is set."
