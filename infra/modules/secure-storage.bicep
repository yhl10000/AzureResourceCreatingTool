// ========================================
// Secure Storage Account Module
// SFI-ID4.2.1 Compliant - Shared Key Access Disabled
// ========================================
// This module creates a Storage Account with security best practices:
// - Shared Key Access DISABLED (required for SFI-ID4.2.1)
// - HTTPS only traffic
// - TLS 1.2 minimum
// - Public blob access disabled
// - Cross-tenant replication disabled
// - OAuth authentication by default
// ========================================

@description('Storage account name (3-24 chars, lowercase letters and numbers only)')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Location for the storage account')
param location string = resourceGroup().location

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
  'Standard_GZRS'
  'Standard_RAGZRS'
])
param skuName string = 'Standard_LRS'

@description('Storage account kind')
@allowed([
  'StorageV2'
  'BlobStorage'
  'FileStorage'
  'BlockBlobStorage'
])
param kind string = 'StorageV2'

@description('Access tier for BlobStorage/StorageV2')
@allowed([
  'Hot'
  'Cool'
])
param accessTier string = 'Hot'

@description('Enable hierarchical namespace (Data Lake Gen2)')
param enableHns bool = false

@description('Enable NFS v3 protocol')
param enableNfsV3 bool = false

@description('Enable SFTP')
param enableSftp bool = false

@description('Public network access setting')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('IP rules for network ACLs (array of IP addresses or CIDR ranges)')
param ipRules array = []

@description('Virtual network rules (array of subnet resource IDs)')
param virtualNetworkRules array = []

@description('Tags for the resource')
param tags object = {}

// Build IP rules array
var ipRulesConfig = [for ip in ipRules: {
  value: ip
  action: 'Allow'
}]

// Build VNet rules array
var vnetRulesConfig = [for subnetId in virtualNetworkRules: {
  id: subnetId
  action: 'Allow'
}]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: union(tags, {
    'sfi-compliance': 'SFI-ID4.2.1'
    'shared-key-disabled': 'true'
  })
  sku: {
    name: skuName
  }
  kind: kind
  properties: {
    // ============================================
    // SFI-ID4.2.1 CRITICAL SETTING
    // This MUST be false to pass security scan
    // ============================================
    allowSharedKeyAccess: false
    
    // Default to OAuth authentication in Azure Portal
    defaultToOAuthAuthentication: true
    
    // Security best practices
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    
    // Access tier (only for BlobStorage/StorageV2)
    accessTier: accessTier
    
    // Data Lake / NFS / SFTP settings
    isHnsEnabled: enableHns
    isNfsV3Enabled: enableNfsV3
    isSftpEnabled: enableSftp
    
    // Network security
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: publicNetworkAccess == 'Disabled' ? 'Deny' : (length(ipRules) > 0 || length(virtualNetworkRules) > 0 ? 'Deny' : 'Allow')
      ipRules: ipRulesConfig
      virtualNetworkRules: vnetRulesConfig
    }
    
    // Encryption (default Microsoft-managed keys)
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Account'
        }
        table: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Blob Services configuration
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Outputs
@description('Storage Account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Primary blob endpoint')
output primaryBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Primary file endpoint')
output primaryFileEndpoint string = storageAccount.properties.primaryEndpoints.file

@description('Primary queue endpoint')
output primaryQueueEndpoint string = storageAccount.properties.primaryEndpoints.queue

@description('Primary table endpoint')
output primaryTableEndpoint string = storageAccount.properties.primaryEndpoints.table

@description('Primary DFS endpoint (Data Lake)')
output primaryDfsEndpoint string = storageAccount.properties.primaryEndpoints.dfs

@description('All primary endpoints')
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
