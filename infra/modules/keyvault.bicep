// ============================================================================
// keyvault.bicep — the secret home for non-Azure credentials (flag: useKeyVault)
// ============================================================================
// The golden copy is keyless to Azure services (APIM's managed identity calls
// OpenAI + Content Safety — no keys anywhere). But the moment you add a NON-Azure
// provider (Anthropic, Google) or any third-party tool behind the gateway, you have
// a real secret to hold. Key Vault is its home: APIM reads it through a Key Vault
// REFERENCE named value, so the secret never lands in a template, output, or named
// value's plaintext, and rotates without a redeploy.
//
// This module deploys the vault (RBAC-authorized, soft-delete on) and grants APIM's
// managed identity Key Vault Secrets User. It does NOT create any secret — secrets
// are supplied out-of-band (CLI/portal/pipeline), never in Bicep. The multi-provider
// path (scripts/provision-preview.*) stores the Anthropic key here and creates the
// KV-reference named value that points at it.
// ============================================================================

@description('Azure region for the Key Vault.')
param location string

@description('Globally-unique Key Vault name (3-24 chars).')
param keyVaultName string

@description('APIM system-assigned managed identity principal ID — granted Key Vault Secrets User so it can read KV-reference named values.')
param apimPrincipalId string

@description('Enable purge protection. Recommended TRUE for prod/regulated (irreversible once on); leave false for throwaway dev vaults.')
param enablePurgeProtection bool = false

@description('Resource tags.')
param tags object

// Key Vault Secrets User — read secret VALUES (data plane). The minimum APIM needs.
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true // RBAC, not legacy access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    // Purge protection can only be turned ON (never back off), so set it only when asked.
    enablePurgeProtection: enablePurgeProtection ? true : null
  }
}

// APIM MI can read secret values → KV-reference named values resolve at runtime.
resource secretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, apimPrincipalId, keyVaultSecretsUserRoleId)
  scope: vault
  properties: {
    principalId: apimPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

@description('Key Vault name.')
output keyVaultName string = vault.name

@description('Key Vault URI (base for secret identifiers used by KV-reference named values).')
output keyVaultUri string = vault.properties.vaultUri
