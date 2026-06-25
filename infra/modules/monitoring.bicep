// ============================================================================
// monitoring.bicep — Log Analytics workspace + Application Insights
// ============================================================================
// The observability spine. APIM's logger ships token metrics, prompts, and
// completions here; the built-in LLM analytics workbook reads from it. Cost
// attribution (llm-emit-token-metric) lands as custom metrics in App Insights.
// ============================================================================

@description('Azure region for the monitoring resources.')
param location string

@description('Name of the Log Analytics workspace.')
param logAnalyticsName string

@description('Name of the Application Insights component.')
param appInsightsName string

@description('Resource tags applied to every resource.')
param tags object

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

@description('Resource ID of the Log Analytics workspace.')
output logAnalyticsId string = logAnalytics.id

@description('Resource ID of the Application Insights component.')
output appInsightsId string = appInsights.id

@description('Application Insights instrumentation key (used by the APIM logger).')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Application Insights connection string.')
output appInsightsConnectionString string = appInsights.properties.ConnectionString
