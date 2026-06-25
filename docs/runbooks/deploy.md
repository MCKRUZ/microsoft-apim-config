# Runbook: Deploy

Provisions the full AI-governance gateway. See [architecture](../architecture.md).

## Prerequisites

- **Azure CLI** (`az`), logged in to the target subscription.
- **azd** (Azure Developer CLI).
- An **Azure subscription** with rights to deploy at subscription scope.
- Quota for **Cognitive Services** (Azure OpenAI + Content Safety) and **APIM** in the
  target region.

## Resources provisioned

APIM, Azure OpenAI (`gpt-4o` deployment `chat` + `text-embedding-3-small` deployment
`embeddings`), Azure Managed Redis (RediSearch), Azure AI Content Safety, Log Analytics +
App Insights, and two demo team products/subscriptions: `team-research`, `team-platform`.

## Deploy with azd (default)

```bash
azd up
```

- Provisions Bicep at **subscription scope** (creates resource group `rg-<env>`).
- Default tier is **Developer** (~$50/mo, **no SLA**, ~**30–45 min** to provision).
  Developer supports the entire OpenAI-only showcase including the preview surfaces.
- The **postprovision hook runs `scripts/provision-preview.*`** to stand up the preview
  surfaces (MCP, A2A, unified API) that lack stable Bicep types.

## Fallback (no azd)

```bash
az deployment sub create \
  -l <region> \
  -f infra/main.bicep \
  -p infra/main.parameters.json
```

After a fallback deploy, run `scripts/provision-preview.*` and
`scripts/configure-backend-auth.*` manually (azd's postprovision hook is skipped).

## Backend MI auth (required)

The content-safety backend is created **URL-only** in Bicep — its managed-identity auth
is not expressible in the ARM/Bicep schema. Apply it post-deploy:

```bash
scripts/configure-backend-auth.sh    # or .ps1 on Windows
```

(Portal equivalent: *Backends → content-safety-backend → Authorization credentials →
Managed identity → System assigned → Resource ID `https://cognitiveservices.azure.com`*.)
See [content-safety](../controls/content-safety.md).

## Find the gateway URL + a team key

```bash
# Gateway URL
az apim show -g rg-<env> -n <apim-name> --query gatewayUrl -o tsv

# A team subscription key (team identity)
az apim subscription show -g rg-<env> --service-name <apim-name> \
  --sid team-research --query primaryKey -o tsv
```

Smoke-test it:

```
POST https://<apim>.azure-api.net/openai/deployments/chat/chat/completions?api-version=2024-10-21
Header: api-key: <subscription-key>
```

## Soft-delete / purge note

Cognitive Services (OpenAI, Content Safety) and APIM **soft-delete** on deletion.
Redeploying with the **same names** may require **purging** the soft-deleted resources
first, or the deploy will fail on name conflict.
