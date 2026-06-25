// ============================================================================
// apim.bicep — API Management service (the control plane) + logger + external cache
// ============================================================================
// This is the gateway: the one chokepoint every model/tool/agent call passes
// through. It is created with a SYSTEM-ASSIGNED managed identity so it can
// authenticate to Azure OpenAI and Content Safety without any keys (rbac.bicep
// grants the roles). It wires the Redis cache as an external cache (semantic
// caching) and an Application Insights logger (token metrics + prompt/completion
// logging feeding the built-in LLM analytics workbook).
//
// TIER: default 'Developer' (cheapest, supports the entire OpenAI-only showcase
// incl. MCP/A2A/unified preview — no SLA). 'StandardV2' is the production target.
// Token-limit governance is NOT available on the Consumption tier.
// ============================================================================

@description('Azure region for the APIM service.')
param location string

@description('Name of the APIM service (must be globally unique).')
param apimName string

@description('Publisher email shown on the developer portal / notifications.')
param publisherEmail string

@description('Publisher organisation name.')
param publisherName string

@description('APIM SKU. Developer = cheapest full-feature (no SLA). StandardV2 = production. Consumption is unsupported (no token-limit governance).')
@allowed([
  'Developer'
  'BasicV2'
  'StandardV2'
  'PremiumV2'
])
param skuName string = 'Developer'

@description('Number of scale units. Developer is always 1.')
param skuCapacity int = 1

@description('Application Insights resource ID (for the diagnostic link).')
param appInsightsId string

@description('Application Insights instrumentation key (for the APIM logger).')
param appInsightsInstrumentationKey string

@description('Resource ID of the Azure Managed Redis database (its key is read here to build the cache connection string).')
param redisDatabaseId string

@description('Redis hostname.')
param redisHostName string

@description('Resource tags applied to every resource.')
param tags object

// Build the external-cache connection string here (rather than passing a secret
// between modules) so the access key never lands in a module output / deployment log.
var redisConnectionString = '${redisHostName}:10000,password=${listKeys(redisDatabaseId, '2025-04-01').primaryKey},ssl=True,abortConnect=False'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned' // the gateway's identity used to call OpenAI + Content Safety
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Application Insights logger — token metrics, prompts, completions ship here.
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger for LLM token metrics, prompts, and completions.'
    resourceId: appInsightsId
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
  }
}

// Global APIM diagnostic that routes to App Insights. Enabling this (plus per-API
// LLM logging) is what surfaces token usage in the built-in analytics workbook.
resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    verbosity: 'information'
    httpCorrelationProtocol: 'W3C'
  }
}

// External Redis cache for semantic caching. useFromLocation 'default' applies the
// cache across the (single-region) gateway.
resource apimExternalCache 'Microsoft.ApiManagement/service/caches@2025-09-01-preview' = {
  parent: apim
  name: location
  properties: {
    connectionString: redisConnectionString
    useFromLocation: 'default'
    description: 'Azure Managed Redis (RediSearch) external cache for LLM semantic caching.'
  }
}

@description('Resource ID of the APIM service.')
output apimId string = apim.id

@description('Name of the APIM service.')
output apimName string = apim.name

@description('System-assigned managed identity principal ID (for RBAC role assignments).')
output apimPrincipalId string = apim.identity.principalId

@description('Gateway base URL, e.g. https://<apim>.azure-api.net.')
output apimGatewayUrl string = apim.properties.gatewayUrl

@description('Logger resource ID (referenced by per-API diagnostics).')
output apimLoggerId string = apimLogger.id
