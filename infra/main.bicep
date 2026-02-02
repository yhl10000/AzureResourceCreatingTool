// ========================================
// Main Deployment - SFI Compliant Resources
// ========================================
// This is the main deployment file that orchestrates
// the creation of secure Azure resources compliant with
// SFI-ID4.2.1 (Safe Secrets Standard)
// ========================================

targetScope = 'resourceGroup'

// ============================================
// PARAMETERS
// ============================================

@description('Project name used for resource naming')
@minLength(2)
@maxLength(20)
param projectName string

@description('Environment name')
@allowed([
  'dev'
  'test'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

// Resource toggles
@description('Deploy Storage Account')
param deployStorage bool = true

@description('Deploy SQL Server')
param deploySqlServer bool = false

@description('Deploy Key Vault')
param deployKeyVault bool = true

@description('Deploy Cosmos DB')
param deployCosmosDb bool = false

// SQL Server specific parameters (required if deploySqlServer = true)
@description('Azure AD Admin Object ID for SQL Server')
param sqlAadAdminObjectId string = ''

@description('Azure AD Admin Login Name for SQL Server')
param sqlAadAdminLogin string = ''

@description('Azure AD Admin Principal Type for SQL Server')
@allowed([
  'User'
  'Group'
  'Application'
])
param sqlAadAdminPrincipalType string = 'Group'

// Storage specific parameters
@description('Storage Account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageSku string = 'Standard_LRS'

// Key Vault specific parameters
@description('Key Vault SKU')
@allowed([
  'standard'
  'premium'
])
param keyVaultSku string = 'standard'

// Cosmos DB specific parameters
@description('Cosmos DB API type')
@allowed([
  'Sql'
  'MongoDB'
])
param cosmosDbApiType string = 'Sql'

// Deployment timestamp (utcNow can only be used as parameter default)
param deploymentTimestamp string = utcNow('yyyy-MM-dd')

// ============================================
// VARIABLES
// ============================================

// Naming convention: {resourceType}-{projectName}-{environment}
// Storage accounts have special naming (no hyphens, max 24 chars)
var storageAccountName = take(replace('st${projectName}${environment}', '-', ''), 24)
var sqlServerName = 'sql-${projectName}-${environment}'
var keyVaultName = take('kv-${projectName}-${environment}', 24)
var cosmosDbAccountName = 'cosmos-${projectName}-${environment}'

// Common tags for all resources
var commonTags = {
  Project: projectName
  Environment: environment
  SecurityCompliance: 'SFI-ID4.2.1'
  ManagedBy: 'Bicep'
  CreatedDate: deploymentTimestamp
}

// ============================================
// MODULES
// ============================================

// Storage Account
module storageAccount 'modules/secure-storage.bicep' = if (deployStorage) {
  name: 'deploy-storage-${projectName}-${environment}'
  params: {
    storageAccountName: storageAccountName
    location: location
    skuName: storageSku
    kind: 'StorageV2'
    tags: commonTags
  }
}

// SQL Server
module sqlServer 'modules/secure-sql-server.bicep' = if (deploySqlServer && !empty(sqlAadAdminObjectId) && !empty(sqlAadAdminLogin)) {
  name: 'deploy-sql-${projectName}-${environment}'
  params: {
    sqlServerName: sqlServerName
    location: location
    aadAdminObjectId: sqlAadAdminObjectId
    aadAdminLogin: sqlAadAdminLogin
    aadAdminPrincipalType: sqlAadAdminPrincipalType
    tags: commonTags
  }
}

// Key Vault
module keyVault 'modules/secure-keyvault.bicep' = if (deployKeyVault) {
  name: 'deploy-kv-${projectName}-${environment}'
  params: {
    keyVaultName: keyVaultName
    location: location
    skuName: keyVaultSku
    tags: commonTags
  }
}

// Cosmos DB
module cosmosDb 'modules/secure-cosmosdb.bicep' = if (deployCosmosDb) {
  name: 'deploy-cosmos-${projectName}-${environment}'
  params: {
    cosmosDbAccountName: cosmosDbAccountName
    location: location
    apiType: cosmosDbApiType
    tags: commonTags
  }
}

// ============================================
// OUTPUTS
// ============================================

@description('Deployed resource names')
output deployedResources object = {
  storageAccountName: deployStorage ? storageAccount.outputs.storageAccountName : 'not deployed'
  sqlServerName: deploySqlServer ? sqlServer.outputs.sqlServerName : 'not deployed'
  keyVaultName: deployKeyVault ? keyVault.outputs.keyVaultName : 'not deployed'
  cosmosDbAccountName: deployCosmosDb ? cosmosDb.outputs.cosmosDbAccountName : 'not deployed'
}

@description('Storage Account details')
output storageDetails object = deployStorage ? {
  id: storageAccount.outputs.storageAccountId
  name: storageAccount.outputs.storageAccountName
  primaryBlobEndpoint: storageAccount.outputs.primaryBlobEndpoint
} : {}

@description('SQL Server details')
output sqlServerDetails object = deploySqlServer ? {
  id: sqlServer.outputs.sqlServerId
  name: sqlServer.outputs.sqlServerName
  fqdn: sqlServer.outputs.sqlServerFqdn
} : {}

@description('Key Vault details')
output keyVaultDetails object = deployKeyVault ? {
  id: keyVault.outputs.keyVaultId
  name: keyVault.outputs.keyVaultName
  uri: keyVault.outputs.keyVaultUri
} : {}

@description('Cosmos DB details')
output cosmosDbDetails object = deployCosmosDb ? {
  id: cosmosDb.outputs.cosmosDbAccountId
  name: cosmosDb.outputs.cosmosDbAccountName
  endpoint: cosmosDb.outputs.documentEndpoint
} : {}
