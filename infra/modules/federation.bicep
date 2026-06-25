// ============================================================================
// federation.bicep — per-business-unit workspaces + scoped RBAC (Phase 4)
// ============================================================================
// The org-scale governance model: central control, BU autonomy. Each workspace is
// a "folder" a business-unit team owns — its own APIs, products, subscriptions,
// named values — with Entra RBAC scoped to just that workspace. The platform team
// keeps the global policy floor (governance-global.bicep); BUs inherit it via
// <base /> and can only add NARROWER policies, never strip the central ones.
//
// ⚠ TIER REQUIREMENT: workspaces are supported ONLY on Basic v2 / Standard v2 /
//    Premium / Premium v2 — NOT the Developer tier the seed defaults to. Deploying
//    this with apimSkuName=Developer WILL FAIL. Set a v2 tier for any profile that
//    turns the workspaces flag on (test/prod/regulated). See docs/runbooks/federation.md.
//
// This module also assigns the built-in Azure Policy that enforces <base />
// inheritance, closing the federation loop from the outside.
// ============================================================================

@description('Name of the parent APIM service (existing). Must be a v2 / Premium tier for workspaces.')
param apimName string

@description('Per-BU workspace definitions: { name, displayName, description, adminGroupId }. adminGroupId is an Entra GROUP object id granted Workspace Contributor (leave empty to create the workspace without an RBAC assignment).')
param workspaceDefs array

@description('Effect for the built-in <base/>-inheritance Azure Policy. Audit to start; Deny to hard-block non-inheriting policies.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param basePolicyEffect string = 'Audit'

// Built-in role: API Management Workspace Contributor (assign at workspace scope).
var workspaceContributorRoleId = '0c34c906-8d99-4cb7-8bb7-33f5b0a1a799'
// Built-in Azure Policy: "API Management policies should inherit parent scope using <base/>".
var baseInheritancePolicyId = 'd5448c98-e503-4fdd-bcd2-784960c00d04'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// One workspace per business unit.
resource workspaces 'Microsoft.ApiManagement/service/workspaces@2024-05-01' = [for ws in workspaceDefs: {
  parent: apim
  name: ws.name
  properties: {
    displayName: ws.displayName
    description: ws.description
  }
}]

// Each workspace inherits the global floor via <base /> (the federation contract).
resource workspacePolicies 'Microsoft.ApiManagement/service/workspaces/policies@2024-05-01' = [for (ws, i) in workspaceDefs: {
  parent: workspaces[i]
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/workspace-base.xml')
  }
}]

// Scoped RBAC: grant the BU's Entra group Workspace Contributor on its workspace only.
// (A workspace collaborator also needs a service-scoped workspace role — see the runbook.)
resource workspaceRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (ws, i) in workspaceDefs: if (!empty(ws.adminGroupId)) {
  name: guid(workspaces[i].id, ws.adminGroupId, workspaceContributorRoleId)
  scope: workspaces[i]
  properties: {
    principalId: ws.adminGroupId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', workspaceContributorRoleId)
    principalType: 'Group'
  }
}]

// Enforce <base /> inheritance from the outside: a BU policy that drops <base /> is
// audited (or denied) by Azure Policy, so a central control can never be silently bypassed.
resource baseInheritance 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'apim-base-inheritance'
  properties: {
    displayName: 'APIM policies must inherit parent scope using <base/>'
    description: 'Audits/denies any APIM policy section missing <base/>, so workspace/BU policies cannot bypass central controls.'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', baseInheritancePolicyId)
    parameters: {
      effect: {
        value: basePolicyEffect
      }
    }
  }
}

@description('Names of the workspaces created.')
output workspaceNames array = [for (ws, i) in workspaceDefs: workspaces[i].name]
