// ============================================================================
// llm-api.bicep — the governed Azure OpenAI API + backends + four-control policy
// ============================================================================
// Imports Azure OpenAI as a governed API, wires the two supporting backends the
// policy references, and attaches policies/llm-governance.xml (the four GA
// controls). This is where the control plane meets the model.
//
// Managed-identity auth model:
//   - Chat call    -> authenticated by the <authentication-managed-identity> policy
//                     inside llm-governance.xml (API serviceUrl points at OpenAI).
//   - Embeddings   -> authenticated by the embeddings-backend-auth="system-assigned"
//                     attribute on the llm-semantic-cache-lookup policy.
//   - Content Safety -> the llm-content-safety policy calls 'content-safety-backend'
//                     as a black box, so MI must live on the BACKEND ENTITY. That is
//                     NOT expressible in the ARM/Bicep backend schema (verified: even
//                     2025-09-01-preview credentials has no managedIdentity field), so
//                     the backend is created URL-only here and its MI auth is set by
//                     scripts/configure-backend-auth.* post-deploy. See docs/caveats.md.
// ============================================================================

@description('Name of the parent APIM service.')
param apimName string

@description('Azure OpenAI data-plane endpoint, e.g. https://<sub>.openai.azure.com/.')
param openAiEndpoint string

@description('Chat deployment name (alias used in the operation URL template default).')
param chatDeploymentName string

@description('Embeddings deployment name (used to build the embeddings backend URL).')
param embeddingsDeploymentName string

@description('Content Safety endpoint, e.g. https://<cs>.cognitiveservices.azure.com/.')
param contentSafetyEndpoint string

@description('APIM logger resource ID (for the per-API App Insights diagnostic).')
param apimLoggerId string

@description('Azure OpenAI REST api-version the governed API targets.')
param openAiApiVersion string = '2024-10-21'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// --- Backends referenced by the governance policy ---------------------------

// Embeddings backend — semantic cache vectorises prompts here. MI auth is supplied
// by the cache policy's embeddings-backend-auth attribute, so URL-only is correct.
resource embeddingsBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'embeddings-backend'
  properties: {
    protocol: 'http'
    url: '${openAiEndpoint}openai/deployments/${embeddingsDeploymentName}/embeddings'
    description: 'Azure OpenAI embeddings deployment used by llm-semantic-cache-lookup.'
  }
}

// Content Safety backend — URL must be the bare cognitiveservices host (no path).
// MI auth is applied post-deploy (ARM-schema gap), see module header + caveats.md.
resource contentSafetyBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'content-safety-backend'
  properties: {
    protocol: 'http'
    url: contentSafetyEndpoint
    description: 'Azure AI Content Safety (Prompt Shields) backend used by llm-content-safety. MI auth set post-deploy.'
  }
}

// --- The governed API -------------------------------------------------------

resource openAiApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'azure-openai'
  properties: {
    displayName: 'Azure OpenAI (Governed)'
    description: 'Azure OpenAI chat completions, governed by the four AI-gateway controls. Every agent call passes through here — nothing reaches the model directly.'
    path: 'openai'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    // serviceUrl points at the Azure OpenAI data plane; the governance policy adds
    // the managed-identity Authorization header.
    serviceUrl: '${openAiEndpoint}openai'
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'subscription-key'
    }
  }
}

// Chat completions operation (OpenAI schema -> the llm-* policies recognise it).
resource chatCompletionsOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: openAiApi
  name: 'chat-completions'
  properties: {
    displayName: 'Creates a completion for the chat message'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        description: 'Deployment id of the model (e.g. "${chatDeploymentName}").'
        type: 'string'
        required: true
        defaultValue: chatDeploymentName
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          description: 'Azure OpenAI REST API version.'
          type: 'string'
          required: true
          defaultValue: openAiApiVersion
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'OK'
      }
    ]
  }
}

// Attach the four-control governance policy at the API scope.
resource openAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: openAiApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/llm-governance.xml')
  }
  dependsOn: [
    embeddingsBackend
    contentSafetyBackend
  ]
}

// Per-API App Insights diagnostic — surfaces token usage in the built-in LLM workbook.
resource openAiApiDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  parent: openAiApi
  name: 'applicationinsights'
  properties: {
    loggerId: apimLoggerId
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    verbosity: 'information'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
  }
}

@description('Name of the governed Azure OpenAI API.')
output apiName string = openAiApi.name

@description('Relative path of the governed API (clients call https://<gateway>/openai/...).')
output apiPath string = openAiApi.properties.path
