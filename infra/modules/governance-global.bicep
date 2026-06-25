// ============================================================================
// governance-global.bicep — the platform-team all-APIs policy floor (Phase 4)
// ============================================================================
// Creates the GLOBAL (All APIs) policy every scope inherits via <base />, and the
// Entra named values it references. This is the central-control half of federation:
// the guardrails live here, business units inherit them, and the <base/>-inheritance
// Azure Policy (assigned in federation.bicep) stops anyone dropping the inheritance.
//
// entraAuth toggles the JWT requirement: the global policy XML is assembled at
// deploy time by splicing the validate-jwt fragment into the ENTRA_JWT marker only
// when the flag is on, so a disabled control leaves no dead policy behind.
//
// Deployed in every profile (the floor should always exist). When entraAuth is off
// (dev), the policy is just <base/> + a correlation header — benign.
// ============================================================================

@description('Name of the parent APIM service (existing).')
param apimName string

@description('Require an Entra ID JWT on every API (the security-identity floor).')
param entraAuth bool = false

@description('Entra (Azure AD) tenant ID used to validate tokens. Defaults to the deploying tenant.')
param entraTenantId string = ''

@description('Accepted audience (aud claim) for inbound tokens, e.g. api://apim-ai-gateway.')
param entraAudience string = ''

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// Entra named values — only created when JWT validation is on (the fragment that
// references {{entra-tenant-id}} / {{entra-audience}} is only injected then).
resource nvEntraTenant 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = if (entraAuth) {
  parent: apim
  name: 'entra-tenant-id'
  properties: {
    displayName: 'entra-tenant-id'
    value: empty(entraTenantId) ? tenant().tenantId : entraTenantId
  }
}

resource nvEntraAudience 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = if (entraAuth) {
  parent: apim
  name: 'entra-audience'
  properties: {
    displayName: 'entra-audience'
    value: empty(entraAudience) ? 'api://apim-ai-gateway' : entraAudience
  }
}

// Assemble the global policy: inject the JWT fragment only when entraAuth is on.
// Both loadTextContent paths are compile-time constants, so the ternary is allowed.
var globalPolicyXml = replace(
  loadTextContent('../policies/global-governance.xml'),
  '<!-- ENTRA_JWT -->',
  entraAuth ? loadTextContent('../policies/fragments/entra-jwt.xml') : ''
)

resource globalPolicy 'Microsoft.ApiManagement/service/policies@2024-05-01' = {
  parent: apim
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: globalPolicyXml
  }
  // Named values must exist before the policy that references them is validated.
  dependsOn: [
    nvEntraTenant
    nvEntraAudience
  ]
}
