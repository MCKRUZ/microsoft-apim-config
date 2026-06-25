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

@description('Mask secret-bearing headers/query params in the App Insights diagnostic (Phase 3 dataMasking flag). NOTE: APIM data masking covers headers + query params only — it cannot mask prompt/completion BODY content. Body PII is governed by whether LLM message logging is enabled (promptLogging). See docs/caveats.md.')
param dataMasking bool = false

@description('Route chat through a circuit-breaker-protected load-balanced backend pool (Phase 5 modelFailover flag). With one OpenAI account the pool has one member; the circuit breaker still protects it and the pool is ready for a second region.')
param modelFailover bool = false

// --- GA control toggles (compose llm-governance.xml). All default ON so the
//     composed policy reproduces the always-on seed. ---------------------------
@description('Per-minute TPM rate limit (llm-token-limit tokens-per-minute).')
param tokenRateLimit bool = true

@description('Monthly token quota (llm-token-limit token-quota).')
param tokenQuota bool = true

@description('Reject oversize prompts pre-flight (estimate-prompt-tokens).')
param preflightReject bool = true

@description('Emit per-team token metrics (llm-emit-token-metric).')
param costAttribution bool = true

@description('Screen requests with Prompt Shields (llm-content-safety shield-prompt).')
param contentSafetyPrompt bool = true

@description('Screen completions on the way out (enforce-on-completions).')
param contentSafetyResponse bool = true

@description('Semantic cache lookup + store (llm-semantic-cache-*).')
param semanticCache bool = true

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

// --- Model-failover backends (Phase 5) --------------------------------------
// A circuit-breaker-protected chat backend + a load-balanced pool. The breaker
// trips the backend on a burst of 429s/5xx (honouring Retry-After) so a throttling
// or failing model returns fast instead of piling up, then auto-recovers. The pool
// is the failover container — add a second region's backend as a member for
// active-active. Only created when modelFailover is on; the governed policy is then
// routed through the pool via the FAILOVER_BACKEND injection below.
resource chatBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = if (modelFailover) {
  parent: apim
  name: 'chat-backend'
  properties: {
    protocol: 'http'
    url: '${openAiEndpoint}openai'
    description: 'Azure OpenAI chat backend, circuit-breaker protected. Member of openai-pool.'
    circuitBreaker: {
      rules: [
        {
          name: 'throttle-and-5xx'
          failureCondition: {
            count: 3
            interval: 'PT5M'
            statusCodeRanges: [
              {
                min: 429
                max: 429
              }
              {
                min: 500
                max: 599
              }
            ]
          }
          tripDuration: 'PT1M'
          acceptRetryAfter: true // honour Azure OpenAI's Retry-After on 429 throttling
        }
      ]
    }
  }
}

resource openAiPool 'Microsoft.ApiManagement/service/backends@2024-05-01' = if (modelFailover) {
  parent: apim
  name: 'openai-pool'
  properties: {
    description: 'Load-balanced pool of Azure OpenAI backends. Add a second region as a member for active-active failover.'
    type: 'Pool'
    pool: {
      services: [
        {
          id: chatBackend.id
          priority: 1
          weight: 100
        }
      ]
    }
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

// --- Compose the governance policy from the control flags --------------------
// Each block is spliced into its marker in llm-governance.xml only when its flag
// is on; empty string otherwise (no dead policy). All flags default on, so the
// composed policy reproduces the always-on seed byte-for-byte.
var failoverBlock = modelFailover ? '<set-backend-service backend-id="openai-pool" />' : ''

var rateAttr = tokenRateLimit ? ' tokens-per-minute="{{tokens-per-minute}}"' : ''
var quotaAttr = tokenQuota ? ' token-quota="{{token-quota}}" token-quota-period="{{token-quota-period}}"' : ''
var estimateVal = preflightReject ? 'true' : 'false'
var tokenLimitBlock = (tokenRateLimit || tokenQuota) ? '<llm-token-limit counter-key="@(context.Subscription?.Id ?? "anonymous")"${rateAttr}${quotaAttr} estimate-prompt-tokens="${estimateVal}" remaining-tokens-header-name="x-ratelimit-remaining-tokens" remaining-quota-tokens-header-name="x-quota-remaining-tokens" tokens-consumed-header-name="x-tokens-consumed" />' : ''

var emitBlock = costAttribution ? '<llm-emit-token-metric namespace="ai-governance"><dimension name="Subscription" value="@(context.Subscription?.Name ?? "anonymous")" /><dimension name="Product" value="@(context.Product?.Name ?? "none")" /><dimension name="API" value="@(context.Api.Name)" /><dimension name="Client IP" value="@(context.Request.IpAddress)" /><dimension name="Agent ID" value="@(context.Request.Headers.GetValueOrDefault("x-agent-id", "unspecified"))" /></llm-emit-token-metric>' : ''

var csPromptVal = contentSafetyPrompt ? 'true' : 'false'
var csResponseVal = contentSafetyResponse ? 'true' : 'false'
var csBlock = (contentSafetyPrompt || contentSafetyResponse) ? '<llm-content-safety backend-id="content-safety-backend" shield-prompt="${csPromptVal}" enforce-on-completions="${csResponseVal}"><categories output-type="EightSeverityLevels"><category name="Hate" threshold="4" /><category name="Violence" threshold="4" /><category name="SelfHarm" threshold="4" /><category name="Sexual" threshold="4" /></categories></llm-content-safety>' : ''

var cacheLookupBlock = semanticCache ? '<llm-semantic-cache-lookup score-threshold="{{cache-score-threshold}}" embeddings-backend-id="embeddings-backend" embeddings-backend-auth="system-assigned" ignore-system-messages="true" max-message-count="10"><vary-by>@(context.Subscription?.Id ?? "anonymous")</vary-by></llm-semantic-cache-lookup>' : ''
var cacheStoreBlock = semanticCache ? '<llm-semantic-cache-store duration="3600" />' : ''

var composedPolicy = replace(replace(replace(replace(replace(replace(loadTextContent('../policies/llm-governance.xml'), '<!-- FAILOVER_BACKEND -->', failoverBlock), '<!-- TOKEN_LIMIT -->', tokenLimitBlock), '<!-- EMIT_TOKEN_METRIC -->', emitBlock), '<!-- CONTENT_SAFETY -->', csBlock), '<!-- SEMANTIC_CACHE_LOOKUP -->', cacheLookupBlock), '<!-- SEMANTIC_CACHE_STORE -->', cacheStoreBlock)

resource openAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: openAiApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: composedPolicy
  }
  dependsOn: [
    embeddingsBackend
    contentSafetyBackend
    chatBackend
    openAiPool
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
    // Keep subscription keys / bearer tokens out of the telemetry. Masking lives on
    // the per-direction pipeline settings (frontend = client→gateway, backend =
    // gateway→model), NOT at the top level. Hide drops the value entirely. Headers +
    // query params only — APIM cannot mask request/response BODY content.
    frontend: dataMasking ? {
      request: {
        dataMasking: {
          headers: [
            {
              mode: 'Hide'
              value: 'api-key'
            }
          ]
          queryParams: [
            {
              mode: 'Hide'
              value: 'subscription-key'
            }
          ]
        }
      }
    } : null
    backend: dataMasking ? {
      request: {
        dataMasking: {
          headers: [
            {
              mode: 'Hide'
              value: 'Authorization'
            }
          ]
        }
      }
    } : null
  }
}

@description('Name of the governed Azure OpenAI API.')
output apiName string = openAiApi.name

@description('Relative path of the governed API (clients call https://<gateway>/openai/...).')
output apiPath string = openAiApi.properties.path
