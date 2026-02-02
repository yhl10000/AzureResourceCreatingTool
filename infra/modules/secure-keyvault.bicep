// ========================================
// Secure Key Vault Module
// SFI Compliant - RBAC Authorization Enabled
// ========================================
// This module creates a Key Vault with security best practices:
// - RBAC Authorization ENABLED (access policies disabled)
// - Soft delete enabled with retention
// - Purge protection enabled
// - Network ACLs configurable
// ========================================

@description('Key Vault name (3-24 chars, alphanumeric and hyphens)')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Location for the Key Vault')
param location string = resourceGroup().location

@description('Tenant ID for Key Vault (defaults to current subscription tenant)')
param tenantId string = subscription().tenantId

@description('SKU name')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Enable soft delete')
param enableSoftDelete bool = true

@description('Soft delete retention in days (7-90)')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

@description('Enable purge protection (CANNOT be disabled once enabled)')
param enablePurgeProtection bool = true

@description('Enable deployment (VMs can retrieve certs)')
param enabledForDeployment bool = false

@description('Enable disk encryption (Azure Disk Encryption can retrieve secrets)')
param enabledForDiskEncryption bool = false

@description('Enable template deployment (ARM can retrieve secrets)')
param enabledForTemplateDeployment bool = true

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
}]

// Build VNet rules array
var vnetRulesConfig = [for subnetId in virtualNetworkRules: {
  id: subnetId
  ignoreMissingVnetServiceEndpoint: false
}]

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: union(tags, {
    'sfi-compliance': 'rbac-enabled'
    'access-policies-disabled': 'true'
  })
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    
    // ============================================
    // SFI CRITICAL SETTING: RBAC Authorization
    // Access Policies are DISABLED when this is true
    // Users must be granted RBAC roles to access secrets
    // ============================================
    enableRbacAuthorization: true
    
    // Soft delete and purge protection
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection
    
    // Deployment options
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
    
    // Network settings
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: publicNetworkAccess == 'Disabled' ? 'Deny' : (length(ipRules) > 0 || length(virtualNetworkRules) > 0 ? 'Deny' : 'Allow')
      ipRules: ipRulesConfig
      virtualNetworkRules: vnetRulesConfig
    }
    
    // Access policies are empty because we use RBAC
    accessPolicies: []
  }
}

// Outputs
@description('Key Vault resource ID')
output keyVaultId string = keyVault.id

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault resource group')
output resourceGroupName string = resourceGroup().name
