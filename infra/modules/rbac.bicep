// ============================================================================
// rbac.bicep — grant APIM's managed identity access to OpenAI + Content Safety
// ============================================================================
// Keyless auth: the gateway calls the model and the safety service using its
// system-assigned managed identity. These role assignments are what make that work.
//   - Cognitive Services OpenAI User -> call chat + embeddings deployments
//   - Cognitive Services User        -> call the Content Safety / Prompt Shields API
// ============================================================================

@description('Principal ID of the APIM system-assigned managed identity.')
param apimPrincipalId string

@description('Name of the Azure OpenAI account (same resource group).')
param openAiName string

@description('Name of the Content Safety account (same resource group).')
param contentSafetyName string

// Built-in role definition IDs (stable GUIDs).
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User

resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiName
}

resource contentSafety 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: contentSafetyName
}

resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAi.id, apimPrincipalId, openAiUserRoleId)
  scope: openAi
  properties: {
    principalId: apimPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource contentSafetyRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(contentSafety.id, apimPrincipalId, cognitiveServicesUserRoleId)
  scope: contentSafety
  properties: {
    principalId: apimPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalType: 'ServicePrincipal'
  }
}
