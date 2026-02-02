// ========================================
// Azure Policy Assignments for SFI Compliance
// ========================================
// This Bicep file deploys Azure Policy assignments to enforce
// SFI-ID4.2.1 (Safe Secrets Standard) compliance across your subscription
// ========================================

targetScope = 'subscription'

@description('Policy effect for non-compliant resources')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param policyEffect string = 'Audit'

@description('Location for policy assignment metadata')
param location string = 'eastus'

// ============================================
// BUILT-IN POLICY DEFINITION IDs
// ============================================

// Storage Accounts should prevent shared key access
var storageSharedKeyPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54'

// Azure SQL Database should have Azure AD Only authentication enabled
var sqlAadOnlyPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/abda6d70-9778-44e7-84a8-06713e6db027'

// Key vaults should use RBAC permission model
// Note: This is a custom definition ID - you may need to use audit policy
var keyVaultRbacPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5'

// Cosmos DB accounts should disable local authentication
var cosmosDbLocalAuthPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/5450f5bd-9c72-4390-a9c4-a7aba4edfdd2'

// ============================================
// POLICY ASSIGNMENTS
// ============================================

// 1. Storage Account - Prevent Shared Key Access
resource storageSharedKeyPolicy 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'sfi-storage-no-shared-key'
  location: location
  properties: {
    displayName: '[SFI-ID4.2.1] Storage Accounts should prevent shared key access'
    description: 'Enforces SFI-ID4.2.1 compliance by preventing storage accounts from using shared key access. All access must use Azure AD authentication.'
    policyDefinitionId: storageSharedKeyPolicyId
    parameters: {
      effect: {
        value: policyEffect
      }
    }
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'This storage account allows shared key access which violates SFI-ID4.2.1. Please set allowSharedKeyAccess to false.'
      }
    ]
  }
}

// 2. SQL Server - Azure AD Only Authentication
resource sqlAadOnlyPolicy 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'sfi-sql-aad-only'
  location: location
  properties: {
    displayName: '[SFI] Azure SQL should have Azure AD Only Authentication'
    description: 'Enforces Azure AD only authentication for Azure SQL servers. SQL authentication is not allowed.'
    policyDefinitionId: sqlAadOnlyPolicyId
    parameters: {
      effect: {
        value: policyEffect
      }
    }
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'This SQL Server does not have Azure AD Only authentication enabled. Please enable azureADOnlyAuthentication.'
      }
    ]
  }
}

// 3. Key Vault - RBAC Authorization (using audit-based policy)
resource keyVaultRbacPolicy 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'sfi-keyvault-rbac'
  location: location
  properties: {
    displayName: '[SFI] Key Vault should use RBAC authorization'
    description: 'Enforces RBAC authorization for Key Vault. Access policies should not be used.'
    policyDefinitionId: keyVaultRbacPolicyId
    parameters: {
      effect: {
        value: policyEffect == 'Deny' ? 'Audit' : policyEffect  // This policy may not support Deny
      }
    }
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'This Key Vault does not use RBAC authorization. Please set enableRbacAuthorization to true.'
      }
    ]
  }
}

// 4. Cosmos DB - Disable Local Authentication
resource cosmosDbLocalAuthPolicy 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'sfi-cosmosdb-no-local-auth'
  location: location
  properties: {
    displayName: '[SFI] Cosmos DB should disable local authentication'
    description: 'Enforces Cosmos DB accounts to disable local authentication. All access must use Azure AD.'
    policyDefinitionId: cosmosDbLocalAuthPolicyId
    parameters: {
      effect: {
        value: policyEffect
      }
    }
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'This Cosmos DB account has local authentication enabled. Please set disableLocalAuth to true.'
      }
    ]
  }
}

// ============================================
// OUTPUTS
// ============================================

output policyAssignments array = [
  {
    name: storageSharedKeyPolicy.name
    displayName: storageSharedKeyPolicy.properties.displayName
    effect: policyEffect
  }
  {
    name: sqlAadOnlyPolicy.name
    displayName: sqlAadOnlyPolicy.properties.displayName
    effect: policyEffect
  }
  {
    name: keyVaultRbacPolicy.name
    displayName: keyVaultRbacPolicy.properties.displayName
    effect: policyEffect == 'Deny' ? 'Audit' : policyEffect
  }
  {
    name: cosmosDbLocalAuthPolicy.name
    displayName: cosmosDbLocalAuthPolicy.properties.displayName
    effect: policyEffect
  }
]
