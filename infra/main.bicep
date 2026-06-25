// ============================================================================
// main.bicep — subscription-scope orchestrator for the APIM governance golden copy
// ============================================================================
// Provisions the GA core in dependency order:
//   monitoring -> openai -> redis -> content-safety -> apim -> rbac
//   -> named-values -> llm-api (governed API + four controls) -> products (teams)
//
// The PREVIEW agent surfaces (MCP server, A2A agent API, unified model API) and the
// content-safety backend's managed-identity auth are configured post-deploy by
// scripts/ (see azure.yaml hooks). Those are NOT in this template by design — the
// constructs lack stable ARM/Bicep resource types today (docs/adr/0003).
// ============================================================================

targetScope = 'subscription'

@minLength(1)
@maxLength(24)
@description('Environment name (azd). Used to name the resource group and derive a unique resource token.')
param environmentName string

@description('Azure region for all resources.')
param location string

@description('Publisher email for APIM (developer portal / notifications).')
param apimPublisherEmail string

@description('Publisher organisation name for APIM.')
param apimPublisherName string = 'AI Governance Golden Copy'

@description('APIM SKU. Developer = cheapest full-feature (no SLA, default). StandardV2 = production target. Premium (classic) is required for multi-region (Phase 5); workspaces (Phase 4) require a v2/Premium tier. Consumption is unsupported (no token-limit governance).')
@allowed([
  'Developer'
  'BasicV2'
  'StandardV2'
  'Premium'
  'PremiumV2'
])
param apimSkuName string = 'Developer'

@description('Number of APIM scale units. For availability zones, set to a multiple of the zone count (e.g. 3 for 3 zones).')
param apimCapacity int = 1

@description('Availability zones for the primary region when the availabilityZones flag is on (Premium / Premium v2).')
param apimZones array = [
  '1'
  '2'
  '3'
]

@description('Additional regional gateways when the multiRegion flag is on (Premium CLASSIC only). e.g. [ { location: "westus", sku: { name: "Premium", capacity: 1 }, zones: [ "1", "2", "3" ] } ].')
param additionalLocations array = []

@description('Per-minute token rate limit (TPM) applied per team/subscription.')
param tokensPerMinute int = 1000

@description('Monthly token quota applied per team/subscription. NOTE: counts PER gateway region.')
param tokenQuota int = 1000000

@description('Semantic-cache similarity threshold (lower = stricter match). Start tight.')
param cacheScoreThreshold string = '0.05'

@description('Capability profile. Selects a feature-flag set from infra/config/profiles.json. See docs/enterprise/capability-toggles.md.')
@allowed([
  'dev'
  'test'
  'prod'
  'regulated'
])
param profile string = 'dev'

@description('Per-flag overrides merged over the profile, e.g. { networkIsolation: true }.')
param flagOverrides object = {}

@description('Classic VNet injection mode used when networkIsolation is on (classic tiers). External = public gateway + private backends.')
@allowed([
  'External'
  'Internal'
])
param apimVnetMode string = 'External'

@description('Email that receives SecOps alerts (budget breach, injection spike). Defaults to the APIM publisher email.')
param secOpsEmail string = ''

@description('Budget alert threshold (total tokens per 1h window) before the auto-throttle trigger fires. Applies when secOpsLoop is on.')
param budgetTokensPerHour int = 5000000

@description('Injection-spike alert threshold (count of 403 content-safety blocks per 15m window). Applies when secOpsLoop is on.')
param injection403Threshold int = 20

@description('Entra (Azure AD) tenant ID for JWT validation when entraAuth is on. Defaults to the deploying tenant.')
param entraTenantId string = ''

@description('Accepted token audience (aud) when entraAuth is on, e.g. api://apim-ai-gateway.')
param entraAudience string = ''

@description('Per-BU workspace definitions used when the workspaces flag is on. REQUIRES a v2/Premium tier (not Developer).')
param workspaceDefs array = [
  {
    name: 'retail'
    displayName: 'Retail'
    description: 'Retail business-unit workspace (federated APIs/agents).'
    adminGroupId: ''
  }
  {
    name: 'networkops'
    displayName: 'Network Ops'
    description: 'Network Operations business-unit workspace.'
    adminGroupId: ''
  }
  {
    name: 'finance'
    displayName: 'Finance'
    description: 'Finance business-unit workspace.'
    adminGroupId: ''
  }
]

@description('Effect for the built-in <base/>-inheritance Azure Policy (Phase 4). Audit to start; Deny to hard-block.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param basePolicyEffect string = 'Audit'

@description('Tags applied to every resource.')
param tags object = {
  workload: 'apim-agentic-governance'
  'managed-by': 'bicep'
  environment: environmentName
}

// Resolve the capability flags: profile defaults overlaid with explicit overrides.
var profiles = loadJsonContent('config/profiles.json')
var flags = union(profiles[profile], flagOverrides)
var isolation = bool(flags.networkIsolation)
var apimVnetType = isolation ? apimVnetMode : 'None'
var secOps = bool(flags.secOpsLoop)
var masking = bool(flags.dataMasking)
var federationOn = bool(flags.workspaces)
var entra = bool(flags.entraAuth)
var multiRegion = bool(flags.multiRegion)
var availabilityZones = bool(flags.availabilityZones)
var failover = bool(flags.modelFailover)
var keyVaultOn = bool(flags.useKeyVault)

// Deterministic, globally-unique-ish suffix for resource names.
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var rgName = 'rg-${environmentName}'

var names = {
  apim: 'apim-${resourceToken}'
  openAi: 'aoai-${resourceToken}'
  redis: 'redis-${resourceToken}'
  contentSafety: 'cs-${resourceToken}'
  logAnalytics: 'log-${resourceToken}'
  appInsights: 'appi-${resourceToken}'
  keyVault: 'kv-${resourceToken}'
}

@description('Enable Key Vault purge protection (irreversible). Set true for prod/regulated.')
param keyVaultPurgeProtection bool = false

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: {
    location: location
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
    tags: tags
  }
}

// Phase 1 network isolation foundation — only when the flag is on.
module network 'modules/network.bicep' = if (isolation) {
  scope: rg
  name: 'network'
  params: {
    location: location
    namePrefix: 'aigov-${resourceToken}'
    tags: tags
  }
}

module openai 'modules/openai.bicep' = {
  scope: rg
  name: 'openai'
  params: {
    location: location
    openAiName: names.openAi
    publicNetworkAccess: isolation ? 'Disabled' : 'Enabled'
    tags: tags
  }
}

module redis 'modules/redis.bicep' = {
  scope: rg
  name: 'redis'
  params: {
    location: location
    redisName: names.redis
    tags: tags
  }
}

module contentSafety 'modules/content-safety.bicep' = {
  scope: rg
  name: 'content-safety'
  params: {
    location: location
    contentSafetyName: names.contentSafety
    publicNetworkAccess: isolation ? 'Disabled' : 'Enabled'
    tags: tags
  }
}

module apim 'modules/apim.bicep' = {
  scope: rg
  name: 'apim'
  params: {
    location: location
    apimName: names.apim
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    skuName: apimSkuName
    skuCapacity: apimCapacity
    zones: availabilityZones ? apimZones : []
    additionalLocations: multiRegion ? additionalLocations : []
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    redisDatabaseId: redis.outputs.redisDatabaseId
    redisHostName: redis.outputs.redisHostName
    virtualNetworkType: apimVnetType
    apimSubnetId: isolation ? network!.outputs.apimSubnetId : ''
    tags: tags
  }
}

// Private endpoints + public-access-off close the gateway-bypass gap: with public
// access disabled on the backends, APIM (in the VNet) is the only path to them.
module peOpenAi 'modules/private-endpoint.bicep' = if (isolation) {
  scope: rg
  name: 'pe-openai'
  params: {
    location: location
    name: 'pe-${names.openAi}'
    subnetId: network!.outputs.peSubnetId
    targetResourceId: openai.outputs.openAiId
    groupId: 'account'
    privateDnsZoneIds: [
      network!.outputs.dnsZoneIds[0] // privatelink.openai.azure.com
      network!.outputs.dnsZoneIds[1] // privatelink.cognitiveservices.azure.com
    ]
    tags: tags
  }
}

module peContentSafety 'modules/private-endpoint.bicep' = if (isolation) {
  scope: rg
  name: 'pe-content-safety'
  params: {
    location: location
    name: 'pe-${names.contentSafety}'
    subnetId: network!.outputs.peSubnetId
    targetResourceId: contentSafety.outputs.contentSafetyId
    groupId: 'account'
    privateDnsZoneIds: [
      network!.outputs.dnsZoneIds[1] // privatelink.cognitiveservices.azure.com
    ]
    tags: tags
  }
}

module peRedis 'modules/private-endpoint.bicep' = if (isolation) {
  scope: rg
  name: 'pe-redis'
  params: {
    location: location
    name: 'pe-${names.redis}'
    subnetId: network!.outputs.peSubnetId
    targetResourceId: redis.outputs.redisClusterId
    groupId: 'redisEnterprise'
    privateDnsZoneIds: [
      network!.outputs.dnsZoneIds[2] // privatelink.redis.azure.net
    ]
    tags: tags
  }
}

module rbac 'modules/rbac.bicep' = {
  scope: rg
  name: 'rbac'
  params: {
    apimPrincipalId: apim.outputs.apimPrincipalId
    openAiName: openai.outputs.openAiName
    contentSafetyName: contentSafety.outputs.contentSafetyName
  }
}

module namedValues 'modules/named-values.bicep' = {
  scope: rg
  name: 'named-values'
  params: {
    apimName: apim.outputs.apimName
    tokensPerMinute: tokensPerMinute
    tokenQuota: tokenQuota
    cacheScoreThreshold: cacheScoreThreshold
  }
}

module llmApi 'modules/llm-api.bicep' = {
  scope: rg
  name: 'llm-api'
  params: {
    apimName: apim.outputs.apimName
    openAiEndpoint: openai.outputs.openAiEndpoint
    chatDeploymentName: openai.outputs.chatDeploymentName
    embeddingsDeploymentName: openai.outputs.embeddingsDeploymentName
    contentSafetyEndpoint: contentSafety.outputs.contentSafetyEndpoint
    apimLoggerId: apim.outputs.apimLoggerId
    dataMasking: masking
    modelFailover: failover
  }
  // Named values must exist before the policy that references them is validated.
  dependsOn: [
    namedValues
  ]
}

// Phase 3 SecOps loop — Sentinel + diagnostic→LAW + budget/injection alerts → action group.
module secopsModule 'modules/secops.bicep' = if (secOps) {
  scope: rg
  name: 'secops'
  params: {
    location: location
    apimName: apim.outputs.apimName
    workspaceId: monitoring.outputs.logAnalyticsId
    governedApiName: llmApi.outputs.apiName
    actionGroupEmail: empty(secOpsEmail) ? apimPublisherEmail : secOpsEmail
    budgetTokensPerHour: budgetTokensPerHour
    injection403Threshold: injection403Threshold
    tags: tags
  }
}

// Phase 6 — Key Vault: the secret home for non-Azure provider keys (multi-provider).
// Wires the long-declared useKeyVault flag. APIM MI gets Key Vault Secrets User so it
// can read KV-reference named values. Secrets are added out-of-band, never in Bicep.
module keyVault 'modules/keyvault.bicep' = if (keyVaultOn) {
  scope: rg
  name: 'keyvault'
  params: {
    location: location
    keyVaultName: names.keyVault
    apimPrincipalId: apim.outputs.apimPrincipalId
    enablePurgeProtection: keyVaultPurgeProtection
    tags: tags
  }
}

// Microsoft Defender for APIs — SUBSCRIPTION-scope plan (threat protection on APIM).
// Standard tier bills per subscription on API traffic; gated on the flag. Onboarding
// individual APIM APIs to Defender is a second, recommendation-driven step (portal).
resource defenderForApis 'Microsoft.Security/pricings@2024-01-01' = if (secOps) {
  name: 'Api'
  properties: {
    pricingTier: 'Standard'
    subPlan: 'P1'
  }
}

module products 'modules/products.bicep' = {
  scope: rg
  name: 'products'
  params: {
    apimName: apim.outputs.apimName
    apiName: llmApi.outputs.apiName
  }
}

// Phase 4 — the platform-team global policy floor (All APIs). Deployed in every
// profile; entraAuth toggles the Entra JWT requirement spliced into it.
module governanceGlobal 'modules/governance-global.bicep' = {
  scope: rg
  name: 'governance-global'
  params: {
    apimName: apim.outputs.apimName
    entraAuth: entra
    entraTenantId: entraTenantId
    entraAudience: entraAudience
  }
}

// Phase 4 — federation: per-BU workspaces + scoped RBAC + the <base/>-inheritance
// Azure Policy. Workspaces REQUIRE a v2/Premium tier (not Developer) — see runbook.
module federation 'modules/federation.bicep' = if (federationOn) {
  scope: rg
  name: 'federation'
  params: {
    apimName: apim.outputs.apimName
    workspaceDefs: workspaceDefs
    basePolicyEffect: basePolicyEffect
  }
}

// --- Outputs consumed by scripts/ and the operator ---------------------------

@description('Resource group name.')
output AZURE_RESOURCE_GROUP string = rg.name

@description('APIM service name (used by provision-preview + configure-backend-auth scripts).')
output APIM_NAME string = apim.outputs.apimName

@description('APIM gateway base URL — agents call https://<this>/openai/...')
output APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl

@description('Name of the governed Azure OpenAI API.')
output GOVERNED_API_NAME string = llmApi.outputs.apiName

@description('Content Safety account name (configure-backend-auth grants/uses MI here).')
output CONTENT_SAFETY_NAME string = contentSafety.outputs.contentSafetyName

@description('Azure OpenAI account name.')
output OPENAI_NAME string = openai.outputs.openAiName

@description('Key Vault name (empty unless useKeyVault is on). Stores non-Azure provider keys; provision-preview adds the Anthropic key + KV-reference named value here.')
output KEY_VAULT_NAME string = keyVaultOn ? keyVault!.outputs.keyVaultName : ''

@description('Whether multi-provider (preview, v2-only) is intended for this environment. provision-preview reads this to print the Claude/unified-doorway guidance.')
output MULTI_PROVIDER_INTENDED bool = bool(flags.multiProvider)
