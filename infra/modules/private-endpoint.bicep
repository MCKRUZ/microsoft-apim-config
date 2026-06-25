// ============================================================================
// private-endpoint.bicep — reusable private endpoint + private DNS zone group
// ============================================================================
// Creates a private endpoint for a target PaaS resource and links it to one or
// more existing private DNS zones (created in network.bicep). Used to give APIM
// a private path to Azure OpenAI, Content Safety, and Azure Managed Redis once
// their public network access is disabled (closing the gateway-bypass gap).
// ============================================================================

@description('Azure region.')
param location string

@description('Name of the private endpoint.')
param name string

@description('Subnet resource ID to host the private endpoint NIC.')
param subnetId string

@description('Resource ID of the target PaaS resource (e.g. the Azure OpenAI account).')
param targetResourceId string

@description('Private Link group ID for the target (e.g. "account" for Cognitive Services, "redisEnterprise" for Azure Managed Redis).')
param groupId string

@description('Private DNS zone resource IDs to associate (one config per zone).')
param privateDnsZoneIds array

@description('Resource tags.')
param tags object

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-conn'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
  }
}

// Auto-register the PE's private IP in the supplied private DNS zone(s).
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for (zoneId, i) in privateDnsZoneIds: {
        name: 'config-${i}'
        properties: {
          privateDnsZoneId: zoneId
        }
      }
    ]
  }
}

@description('Resource ID of the created private endpoint.')
output privateEndpointId string = privateEndpoint.id
