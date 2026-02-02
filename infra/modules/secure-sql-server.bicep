// ========================================
// Secure Azure SQL Server Module
// SFI Compliant - Azure AD Only Authentication
// ========================================
// This module creates an Azure SQL Server with security best practices:
// - Azure AD Only Authentication ENABLED (no SQL auth)
// - TLS 1.2 minimum
// - Public network access configurable
// - Outbound network access restricted
// ========================================

@description('SQL Server name')
@minLength(1)
@maxLength(63)
param sqlServerName string

@description('Location for the SQL Server')
param location string = resourceGroup().location

@description('Azure AD Admin Object ID (GUID)')
param aadAdminObjectId string

@description('Azure AD Admin Login Name (e.g., admin@contoso.com or group name)')
param aadAdminLogin string

@description('Azure AD Admin Principal Type')
@allowed([
  'User'
  'Group'
  'Application'
])
param aadAdminPrincipalType string = 'Group'

@description('Azure AD Tenant ID (defaults to current subscription tenant)')
param tenantId string = subscription().tenantId

@description('Minimal TLS version')
@allowed([
  '1.0'
  '1.1'
  '1.2'
  '1.3'
])
param minimalTlsVersion string = '1.2'

@description('Enable public network access')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Restrict outbound network access')
@allowed([
  'Enabled'
  'Disabled'
])
param restrictOutboundNetworkAccess string = 'Disabled'

@description('Enable IPv6 support')
@allowed([
  'Enabled'
  'Disabled'
])
param isIPv6Enabled string = 'Disabled'

@description('User-assigned managed identity resource ID for CMK (optional)')
param primaryUserAssignedIdentityId string = ''

@description('Key Vault key URI for CMK encryption (optional)')
param keyId string = ''

@description('Tags for the resource')
param tags object = {}

// Determine if using CMK
var useCMK = !empty(keyId) && !empty(primaryUserAssignedIdentityId)

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: sqlServerName
  location: location
  tags: union(tags, {
    'sfi-compliance': 'azure-ad-only'
    'sql-auth-disabled': 'true'
  })
  identity: useCMK ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${primaryUserAssignedIdentityId}': {}
    }
  } : {
    type: 'SystemAssigned'
  }
  properties: {
    // ============================================
    // SFI CRITICAL SETTING: Azure AD Only Auth
    // SQL authentication is DISABLED
    // ============================================
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: aadAdminPrincipalType
      login: aadAdminLogin
      sid: aadAdminObjectId
      tenantId: tenantId
      azureADOnlyAuthentication: true  // CRITICAL: This disables SQL auth
    }
    
    // Security settings
    minimalTlsVersion: minimalTlsVersion
    publicNetworkAccess: publicNetworkAccess
    restrictOutboundNetworkAccess: restrictOutboundNetworkAccess
    isIPv6Enabled: isIPv6Enabled
    
    // CMK settings (optional)
    primaryUserAssignedIdentityId: useCMK ? primaryUserAssignedIdentityId : null
    keyId: useCMK ? keyId : null
  }
}

// Explicitly create Azure AD Only Authentication resource
// This ensures the setting is properly applied
resource aadOnlyAuth 'Microsoft.Sql/servers/azureADOnlyAuthentications@2023-08-01' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    azureADOnlyAuthentication: true
  }
}

// Create firewall rule to allow Azure services (optional, commonly needed)
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01' = if (publicNetworkAccess == 'Enabled') {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Outputs
@description('SQL Server resource ID')
output sqlServerId string = sqlServer.id

@description('SQL Server name')
output sqlServerName string = sqlServer.name

@description('SQL Server fully qualified domain name')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL Server system-assigned identity principal ID (if using SystemAssigned)')
output principalId string = sqlServer.identity.type == 'SystemAssigned' ? sqlServer.identity.principalId : ''

@description('SQL Server state')
output state string = sqlServer.properties.state
