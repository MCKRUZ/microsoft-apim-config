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

@description('APIM SKU. Developer = cheapest full-feature (no SLA, default). StandardV2 = production target. Consumption is unsupported (no token-limit governance).')
@allowed([
  'Developer'
  'BasicV2'
  'StandardV2'
  'PremiumV2'
])
param apimSkuName string = 'Developer'

@description('Per-minute token rate limit (TPM) applied per team/subscription.')
param tokensPerMinute int = 1000

@description('Monthly token quota applied per team/subscription. NOTE: counts PER gateway region.')
param tokenQuota int = 1000000

@description('Semantic-cache similarity threshold (lower = stricter match). Start tight.')
param cacheScoreThreshold string = '0.05'

@description('Tags applied to every resource.')
param tags object = {
  workload: 'apim-agentic-governance'
  'managed-by': 'bicep'
  environment: environmentName
}

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
}

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

module openai 'modules/openai.bicep' = {
  scope: rg
  name: 'openai'
  params: {
    location: location
    openAiName: names.openAi
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
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    redisDatabaseId: redis.outputs.redisDatabaseId
    redisHostName: redis.outputs.redisHostName
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
  }
  // Named values must exist before the policy that references them is validated.
  dependsOn: [
    namedValues
  ]
}

module products 'modules/products.bicep' = {
  scope: rg
  name: 'products'
  params: {
    apimName: apim.outputs.apimName
    apiName: llmApi.outputs.apiName
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
