// ============================================================================
// redis.bicep — Azure Managed Redis with the RediSearch module (semantic cache)
// ============================================================================
// Semantic caching needs an external, RediSearch-capable Redis. CRITICAL CONSTRAINT
// (verified in docs): the RediSearch module can ONLY be enabled when the cache is
// CREATED — you cannot add it to an existing cache. So this module must be right
// the first time; changing it later means recreating the cache.
//
// The cache is wired into APIM as an external cache in apim.bicep using the
// connection string this module outputs.
// ============================================================================

@description('Azure region for the Redis cluster.')
param location string

@description('Name of the Azure Managed Redis (redisEnterprise) cluster.')
param redisName string

@description('SKU. Balanced_B0 is the smallest/cheapest Azure Managed Redis tier.')
param skuName string = 'Balanced_B0'

@description('Resource tags applied to every resource.')
param tags object

resource redisCluster 'Microsoft.Cache/redisEnterprise@2025-04-01' = {
  name: redisName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    minimumTlsVersion: '1.2'
    highAvailability: 'Disabled' // golden-copy/dev default; enable for production resiliency
  }
}

resource redisDatabase 'Microsoft.Cache/redisEnterprise/databases@2025-04-01' = {
  parent: redisCluster
  name: 'default'
  properties: {
    clientProtocol: 'Encrypted' // TLS — required for the APIM external cache connection (ssl=True)
    port: 10000
    clusteringPolicy: 'EnterpriseCluster'
    evictionPolicy: 'NoEviction' // RediSearch indexes require NoEviction
    modules: [
      {
        name: 'RediSearch' // the vector-search module semantic caching depends on
      }
    ]
  }
}

// NOTE: the connection string (which contains the access key) is intentionally NOT
// emitted as a module output — emitting a secret in outputs is a linter failure and
// leaves the key in deployment history. The APIM module reads the key itself via
// listKeys() on this database id when it builds the external-cache connection string.
@description('Resource ID of the Redis database (the APIM module reads its key to build the cache connection string).')
output redisDatabaseId string = redisDatabase.id

@description('Resource ID of the Redis Enterprise cluster (private-endpoint target, group "redisEnterprise").')
output redisClusterId string = redisCluster.id

@description('Redis hostname.')
output redisHostName string = redisCluster.properties.hostName

@description('Redis SSL port.')
output redisPort int = 10000
