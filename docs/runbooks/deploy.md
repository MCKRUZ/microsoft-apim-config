# Runbook: Deploy

Provisions the full AI-governance gateway. See [architecture](../architecture.md).

## Prerequisites

- **Azure CLI** (`az`), the Azure command-line tool, logged in to the target subscription.
- **azd** (Azure Developer CLI), the higher-level tool that wraps a full deploy in one command.
- An **Azure subscription** with rights to deploy across the whole subscription.
- Enough quota for **Cognitive Services** (Azure OpenAI + Content Safety) and the API gateway (Azure API Management, "APIM") in the
  target region.

## Resources provisioned

The API gateway (APIM), Azure OpenAI (`gpt-4o` deployment `chat` + `text-embedding-3-small` deployment
`embeddings`), Azure Managed Redis (RediSearch), Azure AI Content Safety, Log Analytics +
App Insights for monitoring, and two demo team products/subscriptions: `team-research`, `team-platform`.

## Deploy with azd (default)

```bash
azd up
```

- Deploys across the whole subscription (creates resource group `rg-<env>`).
- The default tier is **Developer** (~$50/mo, **no service-level guarantee**, ~**30–45 min** to provision).
  Developer is enough to run the entire OpenAI-only showcase, including the not-yet-final (preview) features.
- After provisioning, a **post-deploy hook runs `scripts/provision-preview.*`** to set up the preview
  features — the standard agents use to reach tools (MCP), agent-to-agent (A2A), and the unified API — which don't yet have stable Bicep definitions.

## Fallback (no azd)

```bash
az deployment sub create \
  -l <region> \
  -f infra/main.bicep \
  -p infra/main.parameters.json
```

After a fallback deploy, run `scripts/provision-preview.*` and
`scripts/configure-backend-auth.*` by hand (the azd post-deploy hook only runs under `azd up`).

## Backend MI auth (required)

The content-safety backend is created with **only its URL** in Bicep, because its sign-in method — an Azure-issued identity the service owns, with no stored password — can't be expressed in the Bicep/ARM templates. Set it up after the deploy:

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

When you delete Cognitive Services (OpenAI, Content Safety) and the API gateway (APIM), Azure doesn't remove them immediately — it keeps them in a recoverable "soft-deleted" state for a while.
If you redeploy with the **same names**, you may first have to **purge** (permanently remove) those soft-deleted resources,
or the new deploy will fail because the names are still taken.
