// ============================================================================
// content-safety.bicep — Azure AI Content Safety account (Prompt Shields)
// ============================================================================
// Backs the llm-content-safety policy. APIM calls this service (via its managed
// identity, see rbac.bicep) to screen prompts/completions for jailbreak,
// indirect prompt-injection, and harm categories before the model is reached.
//
// The policy's content-safety backend must point at:
//   https://<customSubDomain>.cognitiveservices.azure.com
// which requires a custom subdomain on the account (set below) and AAD auth.
// ============================================================================

@description('Azure region for the Content Safety account.')
param location string

@description('Name of the Azure AI Content Safety account.')
param contentSafetyName string

@description('Custom subdomain — required for managed-identity (AAD) auth. Defaults to the account name.')
param customSubDomainName string = contentSafetyName

@description('Public network access. Set to Disabled when network isolation is on (reached only via private endpoint).')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Resource tags applied to every resource.')
param tags object

resource contentSafety 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: contentSafetyName
  location: location
  tags: tags
  kind: 'ContentSafety'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: customSubDomainName
    disableLocalAuth: true // APIM authenticates with managed identity, not keys
    publicNetworkAccess: publicNetworkAccess
    networkAcls: publicNetworkAccess == 'Disabled' ? {
      defaultAction: 'Deny'
    } : null
  }
}

@description('Resource ID of the Content Safety account (used for RBAC role assignment).')
output contentSafetyId string = contentSafety.id

@description('Name of the Content Safety account.')
output contentSafetyName string = contentSafety.name

@description('Content Safety endpoint, e.g. https://<subdomain>.cognitiveservices.azure.com/.')
output contentSafetyEndpoint string = contentSafety.properties.endpoint
