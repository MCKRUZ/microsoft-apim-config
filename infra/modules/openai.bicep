// ============================================================================
// openai.bicep — Azure OpenAI account + chat & embeddings deployments
// ============================================================================
// The governed model backend. Two deployments:
//   - chat       (gpt-4o)               -> the model agents call through the gateway
//   - embeddings (text-embedding-3-small) -> used by semantic caching to vectorise prompts
// Local key auth is DISABLED — APIM authenticates with its managed identity (see rbac.bicep).
// ============================================================================

@description('Azure region for the Azure OpenAI account.')
param location string

@description('Name of the Azure OpenAI (Cognitive Services) account.')
param openAiName string

@description('Custom subdomain — required for managed-identity (AAD) token auth. Defaults to the account name.')
param customSubDomainName string = openAiName

@description('Chat model deployment name (the alias clients/policies reference).')
param chatDeploymentName string = 'chat'

@description('Underlying chat model.')
param chatModelName string = 'gpt-4o'

@description('Chat model version.')
param chatModelVersion string = '2024-11-20'

@description('Tokens-per-minute capacity (thousands) for the chat deployment.')
param chatCapacity int = 20

@description('Embeddings model deployment name (referenced by the semantic-cache policy).')
param embeddingsDeploymentName string = 'embeddings'

@description('Underlying embeddings model.')
param embeddingsModelName string = 'text-embedding-3-small'

@description('Embeddings model version.')
param embeddingsModelVersion string = '1'

@description('Tokens-per-minute capacity (thousands) for the embeddings deployment.')
param embeddingsCapacity int = 20

@description('Resource tags applied to every resource.')
param tags object

resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: customSubDomainName
    // Force managed-identity auth from APIM; no API keys in policies or named values.
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

// Chat deployment — the model the governed LLM API points at.
resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAi
  name: chatDeploymentName
  sku: {
    name: 'Standard'
    capacity: chatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
}

// Embeddings deployment — used by llm-semantic-cache-lookup to vectorise prompts.
// Sequential dependency: a Cognitive Services account allows only one deployment
// operation at a time, so chain embeddings after chat.
resource embeddingsDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAi
  name: embeddingsDeploymentName
  dependsOn: [
    chatDeployment
  ]
  sku: {
    name: 'Standard'
    capacity: embeddingsCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingsModelName
      version: embeddingsModelVersion
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
}

@description('Resource ID of the Azure OpenAI account (used for RBAC role assignment).')
output openAiId string = openAi.id

@description('Name of the Azure OpenAI account.')
output openAiName string = openAi.name

@description('AAD principal/data-plane endpoint, e.g. https://<subdomain>.openai.azure.com/.')
output openAiEndpoint string = openAi.properties.endpoint

@description('Chat deployment name (alias used by the governed LLM API + policies).')
output chatDeploymentName string = chatDeployment.name

@description('Embeddings deployment name (referenced by the semantic-cache embeddings backend).')
output embeddingsDeploymentName string = embeddingsDeployment.name
