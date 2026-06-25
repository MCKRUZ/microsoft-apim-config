// ============================================================================
// products.bicep — per-team products + subscriptions (identity & attribution)
// ============================================================================
// The article's reference path step: "a separate identifier for each team and
// application." Each product gets its own subscription key; that key is the
// team/app identity the governance policy keys spend caps and cost metrics on
// (see llm-emit-token-metric dimensions + llm-token-limit counter-key).
//
// Two teams are created as a demonstration. Add more by extending the `teams`
// parameter — no policy edits needed.
// ============================================================================

@description('Name of the parent APIM service.')
param apimName string

@description('Name of the governed API the products grant access to.')
param apiName string

@description('Teams to onboard. Each becomes a product + subscription (its own key).')
param teams array = [
  {
    id: 'team-research'
    displayName: 'Team Research'
    description: 'Research team — governed access to the Azure OpenAI API.'
  }
  {
    id: 'team-platform'
    displayName: 'Team Platform'
    description: 'Platform team — governed access to the Azure OpenAI API.'
  }
]

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// One product per team. published + subscriptionRequired so a key is needed to call.
resource products 'Microsoft.ApiManagement/service/products@2024-05-01' = [
  for team in teams: {
    parent: apim
    name: team.id
    properties: {
      displayName: team.displayName
      description: team.description
      subscriptionRequired: true
      approvalRequired: false
      state: 'published'
    }
  }
]

// Associate the governed API with each product (stable products/apis child; the
// product name + API name form the link — no apiLinks preview resource needed).
resource productApis 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = [
  for (team, i) in teams: {
    parent: products[i]
    name: apiName
  }
]

// A subscription per team => a distinct subscription key = the team identity the
// governance policy attributes spend and metrics to.
resource subscriptions 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = [
  for (team, i) in teams: {
    parent: apim
    name: '${team.id}-sub'
    properties: {
      displayName: '${team.displayName} subscription'
      scope: products[i].id
      state: 'active'
    }
  }
]

@description('The team product IDs created.')
output teamProductIds array = [for (team, i) in teams: products[i].id]
