// ============================================================================
// secops.bicep — turn telemetry into enforcement (Phase 3, flag: secOpsLoop)
// ============================================================================
// Observability is not governance; the closed loop is. This module deploys:
//   1. A diagnostic setting on APIM → Log Analytics, enabling the GatewayLogs and
//      GatewayLlmLogs categories. GatewayLlmLogs is what populates the
//      ApiManagementGatewayLlmLog table (TotalTokens/PromptTokens/...), the grounded
//      source the budget alert queries. Token COUNTS are metadata, not prompt
//      bodies — safe to collect even in regulated environments. (Logging the
//      prompt/completion MESSAGE bodies is a separate per-API toggle; see
//      docs/runbooks/secops-loop.md and the promptLogging flag.)
//   2. Microsoft Sentinel onboarding on the workspace (SIEM correlation).
//   3. An action group (email + optional webhook → the auto-throttle actuator).
//   4. Two grounded log alerts:
//        - budget threshold  : sum(TotalTokens) over the window > limit
//        - injection spike   : count of 403 (content-safety blocks) > limit
//      Both route to the action group. The budget alert is the trigger for
//      auto-throttle (scripts/throttle.*); see the runbook for wiring the action
//      group to an Automation runbook / Logic App that runs it.
//
// Microsoft Defender for APIs is a SUBSCRIPTION-scope plan and is enabled in
// main.bicep (Microsoft.Security/pricings), not here.
// ============================================================================

@description('Azure region (must match the Log Analytics workspace region).')
param location string

@description('Name of the parent APIM service (existing).')
param apimName string

@description('Resource ID of the Log Analytics workspace (alert scope + diagnostic target).')
param workspaceId string

@description('Name of the governed Azure OpenAI API (used to scope the injection-spike alert).')
param governedApiName string

@description('Email address that receives SecOps alerts (budget breach, injection spike).')
param actionGroupEmail string

@description('Budget alert threshold: total tokens per evaluation window before alerting → auto-throttle.')
param budgetTokensPerHour int = 5000000

@description('Injection-spike alert threshold: number of 403 (content-safety) blocks per window before alerting.')
param injection403Threshold int = 20

@description('Resource tags.')
param tags object

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// (1) Route gateway + LLM resource logs to Log Analytics so the alert queries have
//     data. GatewayLlmLogs => ApiManagementGatewayLlmLog (TotalTokens etc.).
resource apimToLaw 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'secops-to-law'
  scope: apim
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
      {
        category: 'GatewayLlmLogs'
        enabled: true
      }
    ]
  }
}

// (2) Onboard Microsoft Sentinel onto the workspace (SIEM). Extension resource;
//     'default' is the only valid onboarding-state name.
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(workspaceId, '/'))
}

resource sentinel 'Microsoft.SecurityInsights/onboardingStates@2022-08-01' = {
  scope: workspace
  name: 'default'
  properties: {
    customerManagedKey: false
  }
}

// (3) Where alerts go. The webhook receiver is where you wire the auto-throttle
//     actuator (Automation runbook / Logic App running scripts/throttle.*).
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-aigov-secops'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'aigovsecop'
    enabled: true
    emailReceivers: [
      {
        name: 'secops-email'
        emailAddress: actionGroupEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// (4a) Budget threshold → the auto-throttle trigger. Sum of total tokens over the
//      window; breach means a runaway/expensive pattern. Window defines the range
//      (no ago() in the query, to avoid double-counting).
resource budgetAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'aigov-budget-threshold'
  location: location
  tags: tags
  properties: {
    displayName: 'AI governance — token budget threshold (auto-throttle trigger)'
    description: 'Sum of TotalTokens over the window exceeded the budget. Action group can trigger scripts/throttle.* to lower the TPM named value.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    scopes: [
      workspaceId
    ]
    criteria: {
      allOf: [
        {
          query: 'ApiManagementGatewayLlmLog | summarize TokenTotal = sum(TotalTokens)'
          timeAggregation: 'Total'
          metricMeasureColumn: 'TokenTotal'
          operator: 'GreaterThan'
          threshold: budgetTokensPerHour
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// (4b) Injection spike → a wave of content-safety blocks (403) on the governed API
//      is a likely prompt-injection / jailbreak attack. Higher severity.
resource injectionAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'aigov-injection-spike'
  location: location
  tags: tags
  properties: {
    displayName: 'AI governance — content-safety block (403) spike'
    description: 'Unusual volume of 403 blocks on the governed LLM API — possible coordinated prompt-injection / jailbreak attempts.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    scopes: [
      workspaceId
    ]
    criteria: {
      allOf: [
        {
          query: 'ApiManagementGatewayLogs | where ApiId == "${governedApiName}" | where ResponseCode == 403'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: injection403Threshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

@description('Resource ID of the SecOps action group (wire the auto-throttle actuator here).')
output actionGroupId string = actionGroup.id
