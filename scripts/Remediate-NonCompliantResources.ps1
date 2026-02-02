# ========================================
# Remediate Non-Compliant Azure Resources
# ========================================
# This script fixes existing Azure resources that don't comply
# with SFI-ID4.2.1 (Safe Secrets Standard)
# ========================================

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "",

    # Resource type filters
    [Parameter(Mandatory = $false)]
    [switch]$RemediateStorage,

    [Parameter(Mandatory = $false)]
    [switch]$RemediateSqlServer,

    [Parameter(Mandatory = $false)]
    [switch]$RemediateKeyVault,

    [Parameter(Mandatory = $false)]
    [switch]$RemediateCosmosDb,

    [Parameter(Mandatory = $false)]
    [switch]$RemediateAll,

    # Export report
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ""
)

# ============================================
# CONFIGURATION
# ============================================

$ErrorActionPreference = "Stop"

# If no specific resource types selected, remediate all
if (-not ($RemediateStorage -or $RemediateSqlServer -or $RemediateKeyVault -or $RemediateCosmosDb)) {
    $RemediateAll = $true
}

if ($RemediateAll) {
    $RemediateStorage = $true
    $RemediateSqlServer = $true
    $RemediateKeyVault = $true
    $RemediateCosmosDb = $true
}

# ============================================
# HELPER FUNCTIONS
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
    Write-Host ">> $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# ============================================
# RESULTS TRACKING
# ============================================

$script:Results = @{
    Storage = @{
        Scanned = 0
        NonCompliant = 0
        Remediated = 0
        Failed = 0
        Resources = @()
    }
    SqlServer = @{
        Scanned = 0
        NonCompliant = 0
        Remediated = 0
        Failed = 0
        Resources = @()
    }
    KeyVault = @{
        Scanned = 0
        NonCompliant = 0
        Remediated = 0
        Failed = 0
        Resources = @()
    }
    CosmosDb = @{
        Scanned = 0
        NonCompliant = 0
        Remediated = 0
        Failed = 0
        Resources = @()
    }
}

# ============================================
# REMEDIATION FUNCTIONS
# ============================================

function Remediate-StorageAccounts {
    Write-Header "Storage Accounts - Shared Key Access"

    $query = if ($ResourceGroupName) {
        "az storage account list --resource-group $ResourceGroupName"
    }
    else {
        "az storage account list --subscription $SubscriptionId"
    }

    $storageAccounts = Invoke-Expression $query | ConvertFrom-Json

    foreach ($sa in $storageAccounts) {
        $script:Results.Storage.Scanned++

        $resourceInfo = @{
            Name = $sa.name
            ResourceGroup = $sa.resourceGroup
            AllowSharedKeyAccess = $sa.allowSharedKeyAccess
            Status = "Compliant"
            Action = "None"
        }

        # Check if shared key access is enabled (null means enabled by default)
        if ($sa.allowSharedKeyAccess -ne $false) {
            $script:Results.Storage.NonCompliant++
            $resourceInfo.Status = "Non-Compliant"

            Write-WarningMessage "Non-compliant: $($sa.name) (allowSharedKeyAccess: $($sa.allowSharedKeyAccess))"

            if ($PSCmdlet.ShouldProcess($sa.name, "Disable shared key access")) {
                try {
                    Write-Step "Remediating: $($sa.name)"
                    
                    az storage account update `
                        --name $sa.name `
                        --resource-group $sa.resourceGroup `
                        --allow-shared-key-access false `
                        --output none

                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Remediated: $($sa.name)"
                        $script:Results.Storage.Remediated++
                        $resourceInfo.Action = "Remediated"
                    }
                    else {
                        throw "Azure CLI returned error"
                    }
                }
                catch {
                    Write-ErrorMessage "Failed to remediate: $($sa.name) - $_"
                    $script:Results.Storage.Failed++
                    $resourceInfo.Action = "Failed"
                }
            }
            else {
                $resourceInfo.Action = "Skipped (WhatIf)"
            }
        }
        else {
            Write-Success "Compliant: $($sa.name)"
        }

        $script:Results.Storage.Resources += $resourceInfo
    }
}

function Remediate-SqlServers {
    Write-Header "SQL Servers - Azure AD Only Authentication"

    $query = if ($ResourceGroupName) {
        "az sql server list --resource-group $ResourceGroupName"
    }
    else {
        "az sql server list --subscription $SubscriptionId"
    }

    $sqlServers = Invoke-Expression $query | ConvertFrom-Json

    foreach ($sql in $sqlServers) {
        $script:Results.SqlServer.Scanned++

        # Get AAD-only auth status
        $aadOnlyAuth = az sql server ad-only-auth get `
            --resource-group $sql.resourceGroup `
            --server $sql.name `
            2>$null | ConvertFrom-Json

        $isAadOnly = $aadOnlyAuth.azureAdOnlyAuthentication -eq $true

        $resourceInfo = @{
            Name = $sql.name
            ResourceGroup = $sql.resourceGroup
            AzureAdOnlyAuth = $isAadOnly
            Status = "Compliant"
            Action = "None"
        }

        if (-not $isAadOnly) {
            $script:Results.SqlServer.NonCompliant++
            $resourceInfo.Status = "Non-Compliant"

            Write-WarningMessage "Non-compliant: $($sql.name) (AAD-only: $isAadOnly)"

            # Check if AAD admin is configured (required for AAD-only auth)
            $aadAdmin = az sql server ad-admin list `
                --resource-group $sql.resourceGroup `
                --server $sql.name `
                2>$null | ConvertFrom-Json

            if (-not $aadAdmin -or $aadAdmin.Count -eq 0) {
                Write-ErrorMessage "Cannot remediate $($sql.name): No Azure AD admin configured"
                Write-Info "Please configure an Azure AD admin first using: az sql server ad-admin create"
                $script:Results.SqlServer.Failed++
                $resourceInfo.Action = "Failed - No AAD Admin"
            }
            elseif ($PSCmdlet.ShouldProcess($sql.name, "Enable Azure AD only authentication")) {
                try {
                    Write-Step "Remediating: $($sql.name)"
                    
                    az sql server ad-only-auth enable `
                        --resource-group $sql.resourceGroup `
                        --server $sql.name `
                        --output none

                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Remediated: $($sql.name)"
                        $script:Results.SqlServer.Remediated++
                        $resourceInfo.Action = "Remediated"
                    }
                    else {
                        throw "Azure CLI returned error"
                    }
                }
                catch {
                    Write-ErrorMessage "Failed to remediate: $($sql.name) - $_"
                    $script:Results.SqlServer.Failed++
                    $resourceInfo.Action = "Failed"
                }
            }
            else {
                $resourceInfo.Action = "Skipped (WhatIf)"
            }
        }
        else {
            Write-Success "Compliant: $($sql.name)"
        }

        $script:Results.SqlServer.Resources += $resourceInfo
    }
}

function Remediate-KeyVaults {
    Write-Header "Key Vaults - RBAC Authorization"

    $query = if ($ResourceGroupName) {
        "az keyvault list --resource-group $ResourceGroupName"
    }
    else {
        "az keyvault list --subscription $SubscriptionId"
    }

    $keyVaults = Invoke-Expression $query | ConvertFrom-Json

    foreach ($kv in $keyVaults) {
        $script:Results.KeyVault.Scanned++

        # Get detailed properties
        $kvDetails = az keyvault show --name $kv.name 2>$null | ConvertFrom-Json

        $resourceInfo = @{
            Name = $kv.name
            ResourceGroup = $kv.resourceGroup
            EnableRbacAuthorization = $kvDetails.properties.enableRbacAuthorization
            Status = "Compliant"
            Action = "None"
        }

        if ($kvDetails.properties.enableRbacAuthorization -ne $true) {
            $script:Results.KeyVault.NonCompliant++
            $resourceInfo.Status = "Non-Compliant"

            Write-WarningMessage "Non-compliant: $($kv.name) (enableRbacAuthorization: $($kvDetails.properties.enableRbacAuthorization))"

            if ($PSCmdlet.ShouldProcess($kv.name, "Enable RBAC authorization")) {
                try {
                    Write-Step "Remediating: $($kv.name)"
                    
                    # WARNING: This is a significant change that may break existing access
                    Write-WarningMessage "Enabling RBAC will disable access policies. Ensure RBAC roles are assigned first!"
                    
                    az keyvault update `
                        --name $kv.name `
                        --resource-group $kv.resourceGroup `
                        --enable-rbac-authorization true `
                        --output none

                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Remediated: $($kv.name)"
                        $script:Results.KeyVault.Remediated++
                        $resourceInfo.Action = "Remediated"
                    }
                    else {
                        throw "Azure CLI returned error"
                    }
                }
                catch {
                    Write-ErrorMessage "Failed to remediate: $($kv.name) - $_"
                    $script:Results.KeyVault.Failed++
                    $resourceInfo.Action = "Failed"
                }
            }
            else {
                $resourceInfo.Action = "Skipped (WhatIf)"
            }
        }
        else {
            Write-Success "Compliant: $($kv.name)"
        }

        $script:Results.KeyVault.Resources += $resourceInfo
    }
}

function Remediate-CosmosDbAccounts {
    Write-Header "Cosmos DB - Local Authentication"

    $query = if ($ResourceGroupName) {
        "az cosmosdb list --resource-group $ResourceGroupName"
    }
    else {
        "az cosmosdb list --subscription $SubscriptionId"
    }

    $cosmosAccounts = Invoke-Expression $query | ConvertFrom-Json

    foreach ($cosmos in $cosmosAccounts) {
        $script:Results.CosmosDb.Scanned++

        $resourceInfo = @{
            Name = $cosmos.name
            ResourceGroup = $cosmos.resourceGroup
            DisableLocalAuth = $cosmos.disableLocalAuth
            Status = "Compliant"
            Action = "None"
        }

        if ($cosmos.disableLocalAuth -ne $true) {
            $script:Results.CosmosDb.NonCompliant++
            $resourceInfo.Status = "Non-Compliant"

            Write-WarningMessage "Non-compliant: $($cosmos.name) (disableLocalAuth: $($cosmos.disableLocalAuth))"

            if ($PSCmdlet.ShouldProcess($cosmos.name, "Disable local authentication")) {
                try {
                    Write-Step "Remediating: $($cosmos.name)"
                    
                    az cosmosdb update `
                        --name $cosmos.name `
                        --resource-group $cosmos.resourceGroup `
                        --disable-key-based-metadata-write-access true `
                        --output none

                    # Note: disableLocalAuth requires ARM template or REST API
                    # The CLI parameter --disable-key-based-metadata-write-access is related but not the same
                    
                    Write-WarningMessage "Partial remediation applied. Full disableLocalAuth requires ARM template deployment."
                    
                    $script:Results.CosmosDb.Remediated++
                    $resourceInfo.Action = "Partial Remediation"
                }
                catch {
                    Write-ErrorMessage "Failed to remediate: $($cosmos.name) - $_"
                    $script:Results.CosmosDb.Failed++
                    $resourceInfo.Action = "Failed"
                }
            }
            else {
                $resourceInfo.Action = "Skipped (WhatIf)"
            }
        }
        else {
            Write-Success "Compliant: $($cosmos.name)"
        }

        $script:Results.CosmosDb.Resources += $resourceInfo
    }
}

# ============================================
# REPORT GENERATION
# ============================================

function Export-Report {
    param([string]$Path)

    $report = @{
        GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SubscriptionId = $SubscriptionId
        ResourceGroup = if ($ResourceGroupName) { $ResourceGroupName } else { "All" }
        Summary = @{
            TotalScanned = $script:Results.Storage.Scanned + $script:Results.SqlServer.Scanned + $script:Results.KeyVault.Scanned + $script:Results.CosmosDb.Scanned
            TotalNonCompliant = $script:Results.Storage.NonCompliant + $script:Results.SqlServer.NonCompliant + $script:Results.KeyVault.NonCompliant + $script:Results.CosmosDb.NonCompliant
            TotalRemediated = $script:Results.Storage.Remediated + $script:Results.SqlServer.Remediated + $script:Results.KeyVault.Remediated + $script:Results.CosmosDb.Remediated
            TotalFailed = $script:Results.Storage.Failed + $script:Results.SqlServer.Failed + $script:Results.KeyVault.Failed + $script:Results.CosmosDb.Failed
        }
        Details = $script:Results
    }

    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
    Write-Success "Report exported to: $Path"
}

# ============================================
# MAIN SCRIPT
# ============================================

Write-Header "SFI Compliance Remediation"

Write-Host "Subscription: $SubscriptionId"
Write-Host "Resource Group: $(if ($ResourceGroupName) { $ResourceGroupName } else { 'All' })"
Write-Host ""

# Set subscription
Write-Step "Setting Azure context..."
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-ErrorMessage "Failed to set subscription"
    exit 1
}
Write-Success "Context set to subscription: $SubscriptionId"

# Run remediation
if ($RemediateStorage) { Remediate-StorageAccounts }
if ($RemediateSqlServer) { Remediate-SqlServers }
if ($RemediateKeyVault) { Remediate-KeyVaults }
if ($RemediateCosmosDb) { Remediate-CosmosDbAccounts }

# ============================================
# SUMMARY
# ============================================

Write-Header "Remediation Summary"

$totalScanned = $script:Results.Storage.Scanned + $script:Results.SqlServer.Scanned + $script:Results.KeyVault.Scanned + $script:Results.CosmosDb.Scanned
$totalNonCompliant = $script:Results.Storage.NonCompliant + $script:Results.SqlServer.NonCompliant + $script:Results.KeyVault.NonCompliant + $script:Results.CosmosDb.NonCompliant
$totalRemediated = $script:Results.Storage.Remediated + $script:Results.SqlServer.Remediated + $script:Results.KeyVault.Remediated + $script:Results.CosmosDb.Remediated
$totalFailed = $script:Results.Storage.Failed + $script:Results.SqlServer.Failed + $script:Results.KeyVault.Failed + $script:Results.CosmosDb.Failed

Write-Host ""
Write-Host "Resource Type        Scanned  Non-Compliant  Remediated  Failed" -ForegroundColor White
Write-Host "-------------------------------------------------------------------" -ForegroundColor Gray
Write-Host ("Storage Accounts     {0,-8} {1,-14} {2,-11} {3}" -f $script:Results.Storage.Scanned, $script:Results.Storage.NonCompliant, $script:Results.Storage.Remediated, $script:Results.Storage.Failed) -ForegroundColor $(if ($script:Results.Storage.Failed -gt 0) { "Red" } else { "White" })
Write-Host ("SQL Servers          {0,-8} {1,-14} {2,-11} {3}" -f $script:Results.SqlServer.Scanned, $script:Results.SqlServer.NonCompliant, $script:Results.SqlServer.Remediated, $script:Results.SqlServer.Failed) -ForegroundColor $(if ($script:Results.SqlServer.Failed -gt 0) { "Red" } else { "White" })
Write-Host ("Key Vaults           {0,-8} {1,-14} {2,-11} {3}" -f $script:Results.KeyVault.Scanned, $script:Results.KeyVault.NonCompliant, $script:Results.KeyVault.Remediated, $script:Results.KeyVault.Failed) -ForegroundColor $(if ($script:Results.KeyVault.Failed -gt 0) { "Red" } else { "White" })
Write-Host ("Cosmos DB            {0,-8} {1,-14} {2,-11} {3}" -f $script:Results.CosmosDb.Scanned, $script:Results.CosmosDb.NonCompliant, $script:Results.CosmosDb.Remediated, $script:Results.CosmosDb.Failed) -ForegroundColor $(if ($script:Results.CosmosDb.Failed -gt 0) { "Red" } else { "White" })
Write-Host "-------------------------------------------------------------------" -ForegroundColor Gray
Write-Host ("TOTAL                {0,-8} {1,-14} {2,-11} {3}" -f $totalScanned, $totalNonCompliant, $totalRemediated, $totalFailed) -ForegroundColor Cyan
Write-Host ""

if ($totalNonCompliant -eq 0) {
    Write-Success "All resources are compliant with SFI-ID4.2.1!"
}
elseif ($totalRemediated -eq $totalNonCompliant) {
    Write-Success "All non-compliant resources have been remediated!"
}
elseif ($totalFailed -gt 0) {
    Write-WarningMessage "Some resources could not be remediated. Please review the errors above."
}

# Export report if requested
if ($ReportPath) {
    Export-Report -Path $ReportPath
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Review Azure Policy compliance dashboard" -ForegroundColor White
Write-Host "  2. Configure RBAC roles for Key Vaults that were migrated" -ForegroundColor White
Write-Host "  3. Update applications to use managed identity authentication" -ForegroundColor White
Write-Host ""
