// ========================================
// Secure Cosmos DB Account Module
// SFI Compliant - Key Access Disabled
// ========================================
// This module creates a Cosmos DB Account with security best practices:
// - Local authentication (key access) DISABLED
// - Azure AD authentication required
// - Automatic failover enabled
// - Network ACLs configurable
// ========================================

@description('Cosmos DB account name')
@minLength(3)
@maxLength(44)
param cosmosDbAccountName string

@description('Location for the Cosmos DB account')
param location string = resourceGroup().location

@description('Cosmos DB API type')
@allowed([
  'Sql'
  'MongoDB'
  'Cassandra'
  'Gremlin'
  'Table'
])
param apiType string = 'Sql'

@description('Default consistency level')
@allowed([
  'Eventual'
  'ConsistentPrefix'
  'Session'
  'BoundedStaleness'
  'Strong'
])
param defaultConsistencyLevel string = 'Session'

@description('Enable automatic failover')
param enableAutomaticFailover bool = true

@description('Enable multiple write locations')
param enableMultipleWriteLocations bool = false

@description('Secondary location for geo-replication (optional)')
param secondaryLocation string = ''

@description('Enable free tier')
param enableFreeTier bool = false

@description('Public network access setting')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('IP rules for firewall (array of IP addresses or CIDR ranges)')
param ipRules array = []

@description('Virtual network rules (array of subnet resource IDs)')
param virtualNetworkRules array = []

@description('Tags for the resource')
param tags object = {}

// Determine API-specific capabilities using union to handle conditional logic
var mongoCapabilities = apiType == 'MongoDB' ? [{ name: 'EnableMongo' }] : []
var cassandraCapabilities = apiType == 'Cassandra' ? [{ name: 'EnableCassandra' }] : []
var gremlinCapabilities = apiType == 'Gremlin' ? [{ name: 'EnableGremlin' }] : []
var tableCapabilities = apiType == 'Table' ? [{ name: 'EnableTable' }] : []
var capabilities = union(mongoCapabilities, cassandraCapabilities, gremlinCapabilities, tableCapabilities)

// Build locations array
var locations = empty(secondaryLocation) ? [
  {
    locationName: location
    failoverPriority: 0
    isZoneRedundant: false
  }
] : [
  {
    locationName: location
    failoverPriority: 0
    isZoneRedundant: false
  }
  {
    locationName: secondaryLocation
    failoverPriority: 1
    isZoneRedundant: false
  }
]

// Build IP rules
var ipRulesConfig = [for ip in ipRules: {
  ipAddressOrRange: ip
}]

// Build VNet rules
var vnetRulesConfig = [for subnetId in virtualNetworkRules: {
  id: subnetId
  ignoreMissingVNetServiceEndpoint: false
}]

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' = {
  name: cosmosDbAccountName
  location: location
  tags: union(tags, {
    'sfi-compliance': 'local-auth-disabled'
    'key-access-disabled': 'true'
  })
  kind: apiType == 'MongoDB' ? 'MongoDB' : 'GlobalDocumentDB'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // ============================================
    // SFI CRITICAL SETTING: Disable Local Auth
    // Key-based access is DISABLED
    // Azure AD authentication is REQUIRED
    // ============================================
    disableLocalAuth: true
    
    // Database account offer type (Standard is only option)
    databaseAccountOfferType: 'Standard'
    
    // Consistency policy
    consistencyPolicy: {
      defaultConsistencyLevel: defaultConsistencyLevel
      maxIntervalInSeconds: defaultConsistencyLevel == 'BoundedStaleness' ? 300 : 5
      maxStalenessPrefix: defaultConsistencyLevel == 'BoundedStaleness' ? 100000 : 100
    }
    
    // Geo-replication
    locations: locations
    enableAutomaticFailover: enableAutomaticFailover
    enableMultipleWriteLocations: enableMultipleWriteLocations
    
    // Free tier
    enableFreeTier: enableFreeTier
    
    // API capabilities
    capabilities: capabilities
    
    // Network settings
    publicNetworkAccess: publicNetworkAccess
    isVirtualNetworkFilterEnabled: length(virtualNetworkRules) > 0
    ipRules: ipRulesConfig
    virtualNetworkRules: vnetRulesConfig
    
    // Security settings
    minimalTlsVersion: 'Tls12'
    enableAnalyticalStorage: false
    
    // Backup policy
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Geo'
      }
    }
  }
}

// Outputs
@description('Cosmos DB account resource ID')
output cosmosDbAccountId string = cosmosDbAccount.id

@description('Cosmos DB account name')
output cosmosDbAccountName string = cosmosDbAccount.name

@description('Cosmos DB account endpoint')
output documentEndpoint string = cosmosDbAccount.properties.documentEndpoint

@description('Cosmos DB system-assigned identity principal ID')
output principalId string = cosmosDbAccount.identity.principalId
