// ============================================================================
// named-values.bicep — policy parameters surfaced as APIM named values
// ============================================================================
// The governance policy (policies/llm-governance.xml) references {{...}} named
// values so the same policy serves every team/tier without edits. Tune the caps
// here (or via main.parameters.json) rather than touching XML.
//
// All values here are non-secret governance knobs. (Backend credentials use
// managed identity, so there are no secret named values in this golden copy.)
// ============================================================================

@description('Name of the parent APIM service.')
param apimName string

@description('Per-minute token rate limit (TPM) — the "slow down" speed limit.')
param tokensPerMinute int = 1000

@description('Monthly token quota — the "stop" hard budget. Counts PER gateway region/instance.')
param tokenQuota int = 1000000

@description('Quota renewal period in seconds (2592000 = 30 days).')
param tokenQuotaPeriod int = 2592000

@description('Semantic-cache similarity threshold. LOWER = stricter match. Start tight.')
param cacheScoreThreshold string = '0.05'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource nvTokensPerMinute 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'tokens-per-minute'
  properties: {
    displayName: 'tokens-per-minute'
    value: string(tokensPerMinute)
  }
}

resource nvTokenQuota 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'token-quota'
  properties: {
    displayName: 'token-quota'
    value: string(tokenQuota)
  }
}

resource nvTokenQuotaPeriod 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'token-quota-period'
  properties: {
    displayName: 'token-quota-period'
    value: string(tokenQuotaPeriod)
  }
}

resource nvCacheScoreThreshold 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'cache-score-threshold'
  properties: {
    displayName: 'cache-score-threshold'
    value: cacheScoreThreshold
  }
}
