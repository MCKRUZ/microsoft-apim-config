# Runbook — network isolation (Phase 1)

Locks the AI backends (Azure OpenAI, Content Safety, Redis) so they have no public internet address at all — the only thing that can reach them is the API gateway (Azure API Management, "APIM"), over a private network. This closes the "someone bypasses the gateway" risk. It's the `networkIsolation` flag.

## What it deploys (when on)
- A **private network** (a "VNet", `modules/network.bicep`) with one subnet for the gateway (classic injection: no delegation) and one for the private connections, each protected by subnet firewall rules (an "NSG").
- **Private DNS zones** (`privatelink.openai.azure.com`, `privatelink.cognitiveservices.azure.com`, `privatelink.redis.azure.net`) plus links into the private network, so names resolve to the private addresses.
- **Private-only connections** (private endpoints) for Azure OpenAI, Content Safety, and Azure Managed Redis (`modules/private-endpoint.bicep`).
- `publicNetworkAccess: Disabled` + `networkAcls.defaultAction: Deny` on Azure OpenAI and Content Safety — both settings shut off the public door.
- The gateway placed inside the private network via **classic VNet injection** (`virtualNetworkType` = `External` by default, or `Internal`).

With public access turned off, the Azure OpenAI endpoint can't be reached at all except over the private path — so the bypass risk is closed.

## How to turn it on
```bash
# via profile (test/prod/regulated default it on)
azd env set GOV_PROFILE test
azd up

# or override just this flag on any profile
az deployment sub create -l eastus2 -f infra/main.bicep \
  -p infra/main.parameters.json -p flagOverrides='{"networkIsolation":true}'
```
`dev` (the default) leaves it off, keeping the simple public starting template for quick demos.

## ⚠ Validate before production
These settings depend on your environment, tier, and Azure cloud, and `bicep build` can't check whether they're correct for your case — only that they're syntactically valid:

1. **The gateway subnet's firewall rules** (`modules/network.bicep`) are the standard set for classic injection (management on 3443 from `ApiManagement`, load balancer on 6390, gateway on 443; outbound to Storage/KeyVault/Entra/Monitor). Reconcile them against the current [Virtual network configuration reference: API Management](https://learn.microsoft.com/azure/api-management/virtual-network-reference) for your tier before production — Microsoft changes them with platform updates.
2. **Private DNS zone names** — confirm them for your cloud. The **Azure Managed Redis** zone in particular (`privatelink.redis.azure.net` here) should be checked against your `redisEnterprise` deployment; override it with the `privateDnsZoneNames` parameter if it differs.
3. **Tier vs networking mode** — classic injection (what's implemented here) works on **Developer / Premium**. For **Standard v2 / Premium v2**, use VNet *integration* instead (subnet delegated to `Microsoft.Web/serverFarms`) or Premium v2 *injection* (`Microsoft.Web/hostingEnvironments`); see [enterprise/target-architecture §4](../enterprise/target-architecture.md#4-network-isolation-enablenetworkisolation). On Premium v2, injection can only be set when the instance is first created.
4. **External vs Internal** — `External` keeps the gateway reachable from the public internet (simplest, good for validation). `Internal` makes the gateway fully private; in that case put a web entry point with a web application firewall in front of it (Azure Front Door or Application Gateway + WAF — the `edgeWaf` flag, Phase 1b).

## Verify after deploy
- Confirm `publicNetworkAccess = Disabled` on the OpenAI and Content Safety accounts.
- From outside the private network, the OpenAI data endpoint should now refuse the connection (there's no public route to it).
- `scripts/smoke-test.*`, run from a host that can see the private network (or through the gateway), should still pass — proving the gateway still reaches the backends privately even though the public path is gone.
