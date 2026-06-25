# Runbook — network isolation (Phase 1)

Locks the AI backends (Azure OpenAI, Content Safety, Redis) so they have no public internet address at all — the only thing that can reach them is the API gateway (Azure API Management, "APIM"), over a private network. This closes the "someone bypasses the gateway" risk. It's the `networkIsolation` flag.

## What it deploys (when on)
- A **VNet** (`modules/network.bicep`) with an APIM subnet (classic injection: no delegation) and a private-endpoints subnet, each with an NSG.
- **Private DNS zones** (`privatelink.openai.azure.com`, `privatelink.cognitiveservices.azure.com`, `privatelink.redis.azure.net`) + VNet links.
- **Private endpoints** for Azure OpenAI, Content Safety, and Azure Managed Redis (`modules/private-endpoint.bicep`).
- `publicNetworkAccess: Disabled` + `networkAcls.defaultAction: Deny` on Azure OpenAI and Content Safety.
- APIM **classic VNet injection** (`virtualNetworkType` = `External` by default, or `Internal`).

With public access disabled, the Azure OpenAI endpoint is useless without the private path — the bypass risk is closed.

## How to turn it on
```bash
# via profile (test/prod/regulated default it on)
azd env set GOV_PROFILE test
azd up

# or override just this flag on any profile
az deployment sub create -l eastus2 -f infra/main.bicep \
  -p infra/main.parameters.json -p flagOverrides='{"networkIsolation":true}'
```
`dev` (default) leaves it off, preserving the simple public seed for quick demos.

## ⚠ Validate before production
These are environment-/tier-/cloud-sensitive and the `bicep build` cannot check them semantically:

1. **APIM-subnet NSG rules** (`modules/network.bicep`) are the standard classic-injection set (mgmt 3443 from `ApiManagement`, LB 6390, gateway 443; outbound to Storage/KeyVault/Entra/Monitor). Reconcile against the current [Virtual network configuration reference: API Management](https://learn.microsoft.com/azure/api-management/virtual-network-reference) for your tier before prod — they change with platform updates.
2. **Private DNS zone names** — confirm for your cloud. The **Azure Managed Redis** zone in particular (`privatelink.redis.azure.net` here) should be verified against your `redisEnterprise` deployment; override via the `privateDnsZoneNames` param if different.
3. **Tier vs networking mode** — classic injection (implemented here) is **Developer / Premium**. For **Standard v2 / Premium v2**, use VNet *integration* (subnet delegated to `Microsoft.Web/serverFarms`) or Premium v2 *injection* (`Microsoft.Web/hostingEnvironments`); see [enterprise/target-architecture §4](../enterprise/target-architecture.md#4-network-isolation-enablenetworkisolation). Injection on Premium v2 is **create-time only**.
4. **External vs Internal** — `External` keeps the gateway publicly reachable (simplest, good for validation). `Internal` makes the gateway private; front it with Azure Front Door / Application Gateway + WAF (the `edgeWaf` flag, Phase 1b).

## Verify after deploy
- Confirm `publicNetworkAccess = Disabled` on the OpenAI + Content Safety accounts.
- From outside the VNet, the OpenAI data-plane endpoint should now reject (no public route).
- `scripts/smoke-test.*` run from a host with VNet line-of-sight (or through the gateway) should still pass — proving APIM reaches the backends privately while the public path is gone.
