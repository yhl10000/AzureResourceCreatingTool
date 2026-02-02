# ========================================
# Deploy SFI Compliance Policies
# ========================================
# This script deploys Azure Policy assignments to enforce
# SFI-ID4.2.1 (Safe Secrets Standard) compliance
# ========================================

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Audit", "Deny", "Disabled")]
    [string]$PolicyEffect = "Audit",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus"
)

# ============================================
# CONFIGURATION
# ============================================

$ErrorActionPreference = "Stop"

# Built-in Policy Definition IDs
$PolicyDefinitions = @{
    # Storage Accounts should prevent shared key access
    StorageSharedKey = "8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54"
    
    # Azure SQL Database should have Azure AD Only Authentication enabled
    SqlAadOnly = "abda6d70-9778-44e7-84a8-06713e6db027"
    
    # Azure Key Vault should use RBAC permission model
    KeyVaultRbac = "12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5"
    
    # Cosmos DB accounts should disable local authentication
    CosmosDbLocalAuth = "5450f5bd-9c72-4390-a9c4-a7aba4edfdd2"
}

# ============================================
# FUNCTIONS
# ============================================

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "➡️  $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Assign-Policy {
    param(
        [string]$PolicyName,
        [string]$DisplayName,
        [string]$Description,
        [string]$PolicyDefinitionId,
        [string]$Effect,
        [string]$NonComplianceMessage
    )
    
    Write-Step "Assigning policy: $DisplayName"
    
    $scope = "/subscriptions/$SubscriptionId"
    $fullPolicyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$PolicyDefinitionId"
    
    # Check if assignment already exists
    $existingAssignment = Get-AzPolicyAssignment -Name $PolicyName -Scope $scope -ErrorAction SilentlyContinue
    
    if ($existingAssignment) {
        Write-Warning "Policy assignment '$PolicyName' already exists. Updating..."
        
        Set-AzPolicyAssignment `
            -Name $PolicyName `
            -Scope $scope `
            -PolicyParameterObject @{ effect = $Effect } `
            -NonComplianceMessage @{ Message = $NonComplianceMessage } | Out-Null
    }
    else {
        $policyDef = Get-AzPolicyDefinition -Id $fullPolicyDefId -ErrorAction SilentlyContinue
        
        if (-not $policyDef) {
            Write-Error "Policy definition not found: $PolicyDefinitionId"
            return
        }
        
        New-AzPolicyAssignment `
            -Name $PolicyName `
            -DisplayName $DisplayName `
            -Description $Description `
            -Scope $scope `
            -PolicyDefinition $policyDef `
            -PolicyParameterObject @{ effect = $Effect } `
            -Location $Location `
            -NonComplianceMessage @{ Message = $NonComplianceMessage } | Out-Null
    }
    
    Write-Success "Policy assigned: $PolicyName (Effect: $Effect)"
}

# ============================================
# MAIN SCRIPT
# ============================================

Write-Header "SFI Compliance Policy Deployment"

Write-Host "Subscription: $SubscriptionId"
Write-Host "Policy Effect: $PolicyEffect"
Write-Host "Location: $Location"
Write-Host ""

# Connect and set subscription
Write-Step "Setting Azure context..."
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-Success "Context set to subscription: $SubscriptionId"

# 1. Storage Account - Prevent Shared Key Access
Assign-Policy `
    -PolicyName "sfi-storage-no-shared-key" `
    -DisplayName "[SFI-ID4.2.1] Storage Accounts should prevent shared key access" `
    -Description "Enforces SFI-ID4.2.1 compliance by preventing storage accounts from using shared key access." `
    -PolicyDefinitionId $PolicyDefinitions.StorageSharedKey `
    -Effect $PolicyEffect `
    -NonComplianceMessage "This storage account allows shared key access which violates SFI-ID4.2.1. Please set allowSharedKeyAccess to false."

# 2. SQL Server - Azure AD Only Authentication
Assign-Policy `
    -PolicyName "sfi-sql-aad-only" `
    -DisplayName "[SFI] Azure SQL should have Azure AD Only Authentication" `
    -Description "Enforces Azure AD only authentication for Azure SQL servers." `
    -PolicyDefinitionId $PolicyDefinitions.SqlAadOnly `
    -Effect $PolicyEffect `
    -NonComplianceMessage "This SQL Server does not have Azure AD Only authentication enabled."

# 3. Key Vault - RBAC Authorization
$kvEffect = if ($PolicyEffect -eq "Deny") { "Audit" } else { $PolicyEffect }
Assign-Policy `
    -PolicyName "sfi-keyvault-rbac" `
    -DisplayName "[SFI] Key Vault should use RBAC authorization" `
    -Description "Enforces RBAC authorization for Key Vault instead of access policies." `
    -PolicyDefinitionId $PolicyDefinitions.KeyVaultRbac `
    -Effect $kvEffect `
    -NonComplianceMessage "This Key Vault does not use RBAC authorization. Please set enableRbacAuthorization to true."

# 4. Cosmos DB - Disable Local Authentication
Assign-Policy `
    -PolicyName "sfi-cosmosdb-no-local-auth" `
    -DisplayName "[SFI] Cosmos DB should disable local authentication" `
    -Description "Enforces Cosmos DB accounts to disable local authentication." `
    -PolicyDefinitionId $PolicyDefinitions.CosmosDbLocalAuth `
    -Effect $PolicyEffect `
    -NonComplianceMessage "This Cosmos DB account has local authentication enabled. Please set disableLocalAuth to true."

# ============================================
# SUMMARY
# ============================================

Write-Header "Deployment Complete"

Write-Host ""
Write-Host "The following policies have been assigned:" -ForegroundColor White
Write-Host ""
Write-Host "  📦 Storage Accounts - Shared Key Access Disabled ($PolicyEffect)" -ForegroundColor White
Write-Host "  🗄️  SQL Server - Azure AD Only Authentication ($PolicyEffect)" -ForegroundColor White
Write-Host "  🔐 Key Vault - RBAC Authorization ($kvEffect)" -ForegroundColor White
Write-Host "  🌍 Cosmos DB - Local Auth Disabled ($PolicyEffect)" -ForegroundColor White
Write-Host ""

if ($PolicyEffect -eq "Audit") {
    Write-Warning "Policies are in AUDIT mode. Non-compliant resources will be flagged but not blocked."
    Write-Host ""
    Write-Host "To enforce policies, run again with -PolicyEffect 'Deny'" -ForegroundColor Gray
}
elseif ($PolicyEffect -eq "Deny") {
    Write-Success "Policies are in DENY mode. Non-compliant resources will be blocked from creation."
}

Write-Host ""
Write-Host "View compliance status in Azure Portal:" -ForegroundColor Gray
Write-Host "https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyMenuBlade/~/Compliance" -ForegroundColor Blue
Write-Host ""
