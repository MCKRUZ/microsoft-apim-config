// ============================================================================
// network.bicep — Phase 1 network isolation foundation (flag: networkIsolation)
// ============================================================================
// VNet + subnets + NSGs + private DNS zones for the hub. Deployed only when the
// networkIsolation flag is on. Provides:
//   - an APIM subnet (classic VNet injection: NO delegation, NSG attached)
//   - a private-endpoints subnet for backend PEs
//   - private DNS zones so PE private IPs resolve for APIM's managed-identity calls
//
// ⚠ VALIDATE BEFORE PROD:
//   1. The APIM-subnet NSG rules below are the standard classic-injection set, but
//      classic VNet NSG requirements are tier/version-sensitive. Reconcile against
//      "Virtual network configuration reference: API Management" before prod.
//   2. Private DNS zone names are parameterised; the Azure Managed Redis zone in
//      particular varies — confirm for your cloud/region. See docs/runbooks.
// ============================================================================

@description('Azure region.')
param location string

@description('Base name token for network resources.')
param namePrefix string

@description('VNet address space.')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('APIM subnet prefix (classic injection). /27 min, /24 recommended.')
param apimSubnetPrefix string = '10.20.0.0/24'

@description('Private-endpoints subnet prefix.')
param peSubnetPrefix string = '10.20.1.0/24'

@description('Private DNS zone names to create + link (override for sovereign clouds / verify Redis zone).')
param privateDnsZoneNames array = [
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.redis.azure.net'
]

@description('Resource tags.')
param tags object

// NSG for the APIM subnet. Standard classic VNet-injection rule set (external mode):
// the internal load balancer rejects inbound by default, so management + gateway
// inbound must be explicitly allowed; outbound to APIM service dependencies.
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-apim-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Inbound-Management-3443'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Inbound-LB-6390'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Inbound-Gateway-443'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Outbound-Storage-443'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
        }
      }
      {
        name: 'Outbound-KeyVault-443'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
        }
      }
      {
        name: 'Outbound-EntraID-443'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureActiveDirectory'
        }
      }
      {
        name: 'Outbound-Monitor-443'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
        }
      }
    ]
  }
}

// NSG for the private-endpoints subnet (PEs need no special inbound).
resource peNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-pe-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        // Classic VNet injection subnet: must have NO service delegation.
        name: 'snet-apim'
        properties: {
          addressPrefix: apimSubnetPrefix
          networkSecurityGroup: {
            id: apimNsg.id
          }
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: peSubnetPrefix
          networkSecurityGroup: {
            id: peNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Private DNS zones + VNet links so PE private IPs resolve inside the VNet.
resource dnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in privateDnsZoneNames: {
    name: zone
    location: 'global'
    tags: tags
  }
]

resource dnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in privateDnsZoneNames: {
    parent: dnsZones[i]
    name: 'link-${namePrefix}'
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

@description('Resource ID of the APIM subnet (classic injection).')
output apimSubnetId string = vnet.properties.subnets[0].id

@description('Resource ID of the private-endpoints subnet.')
output peSubnetId string = vnet.properties.subnets[1].id

@description('Map of private DNS zone name -> resource ID (for PE zone groups).')
output dnsZoneIds array = [for (zone, i) in privateDnsZoneNames: dnsZones[i].id]

@description('The private DNS zone names, same order as dnsZoneIds.')
output dnsZoneNames array = privateDnsZoneNames
