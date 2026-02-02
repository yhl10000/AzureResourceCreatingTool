# ========================================
# Deploy SFI Compliant Azure Resources
# ========================================
# Main deployment script for creating secure Azure resources
# compliant with SFI-ID4.2.1 (Safe Secrets Standard)
# ========================================

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "test", "staging", "prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",

    # Resource toggles
    [Parameter(Mandatory = $false)]
    [bool]$DeployStorage = $true,

    [Parameter(Mandatory = $false)]
    [bool]$DeploySqlServer = $false,

    [Parameter(Mandatory = $false)]
    [bool]$DeployKeyVault = $true,

    [Parameter(Mandatory = $false)]
    [bool]$DeployCosmosDb = $false,

    # SQL Server parameters (required if DeploySqlServer = $true)
    [Parameter(Mandatory = $false)]
    [string]$SqlAadAdminObjectId = "",

    [Parameter(Mandatory = $false)]
    [string]$SqlAadAdminLogin = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("User", "Group", "Application")]
    [string]$SqlAadAdminPrincipalType = "Group",

    # Optional: Use parameter file instead of individual parameters
    [Parameter(Mandatory = $false)]
    [string]$ParameterFile = "",

    # Skip policy deployment
    [Parameter(Mandatory = $false)]
    [switch]$SkipPolicyDeployment,

    # Policy effect (only used if policies are deployed)
    [Parameter(Mandatory = $false)]
    [ValidateSet("Audit", "Deny", "Disabled")]
    [string]$PolicyEffect = "Audit"
)

# ============================================
# CONFIGURATION
# ============================================

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$InfraDir = Join-Path $RootDir "infra"
$PoliciesDir = Join-Path $RootDir "policies"

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

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-AzureCli {
    try {
        $null = az version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

function Test-BicepCli {
    try {
        $null = az bicep version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

# ============================================
# PREREQUISITES CHECK
# ============================================

Write-Header "Prerequisites Check"

# Check Azure CLI
Write-Step "Checking Azure CLI..."
if (-not (Test-AzureCli)) {
    Write-ErrorMessage "Azure CLI is not installed. Please install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}
Write-Success "Azure CLI is installed"

# Check Bicep
Write-Step "Checking Bicep CLI..."
if (-not (Test-BicepCli)) {
    Write-Info "Installing Bicep CLI..."
    az bicep install
}
Write-Success "Bicep CLI is available"

# Validate SQL Server parameters
if ($DeploySqlServer -and (-not $SqlAadAdminObjectId -or -not $SqlAadAdminLogin)) {
    Write-ErrorMessage "SQL Server deployment requires -SqlAadAdminObjectId and -SqlAadAdminLogin parameters"
    exit 1
}

# ============================================
# AZURE AUTHENTICATION
# ============================================

Write-Header "Azure Authentication"

Write-Step "Checking Azure login status..."
$account = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Info "Not logged in. Initiating Azure login..."
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage "Azure login failed"
        exit 1
    }
}
Write-Success "Logged in to Azure"

Write-Step "Setting subscription to: $SubscriptionId"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-ErrorMessage "Failed to set subscription"
    exit 1
}
Write-Success "Subscription set successfully"

# ============================================
# RESOURCE GROUP
# ============================================

Write-Header "Resource Group Setup"

Write-Step "Checking resource group: $ResourceGroupName"
$rgExists = az group exists --name $ResourceGroupName | ConvertFrom-Json

if (-not $rgExists) {
    if ($PSCmdlet.ShouldProcess($ResourceGroupName, "Create resource group")) {
        Write-Info "Creating resource group in $Location..."
        az group create --name $ResourceGroupName --location $Location --tags "Project=$ProjectName" "Environment=$Environment" "SecurityCompliance=SFI-ID4.2.1"
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage "Failed to create resource group"
            exit 1
        }
        Write-Success "Resource group created"
    }
}
else {
    Write-Success "Resource group already exists"
}

# ============================================
# BICEP VALIDATION
# ============================================

Write-Header "Bicep Template Validation"

$mainBicepPath = Join-Path $InfraDir "main.bicep"

Write-Step "Validating Bicep template..."
az bicep build --file $mainBicepPath --stdout | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-ErrorMessage "Bicep validation failed"
    exit 1
}
Write-Success "Bicep template is valid"

# ============================================
# DEPLOYMENT
# ============================================

Write-Header "Resource Deployment"

$deploymentName = "sfi-deploy-$ProjectName-$Environment-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host ""
Write-Host "Deployment Configuration:" -ForegroundColor White
Write-Host "  Project Name:    $ProjectName" -ForegroundColor White
Write-Host "  Environment:     $Environment" -ForegroundColor White
Write-Host "  Location:        $Location" -ForegroundColor White
Write-Host "  Storage:         $(if ($DeployStorage) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  SQL Server:      $(if ($DeploySqlServer) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  Key Vault:       $(if ($DeployKeyVault) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  Cosmos DB:       $(if ($DeployCosmosDb) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host ""

if ($PSCmdlet.ShouldProcess("$ResourceGroupName", "Deploy Bicep template")) {
    Write-Step "Starting deployment: $deploymentName"

    # Build deployment command
    $deployArgs = @(
        "deployment", "group", "create",
        "--resource-group", $ResourceGroupName,
        "--template-file", $mainBicepPath,
        "--name", $deploymentName
    )

    if ($ParameterFile) {
        # Use parameter file
        $deployArgs += @("--parameters", $ParameterFile)
    }
    else {
        # Use individual parameters
        $deployArgs += @(
            "--parameters",
            "projectName=$ProjectName",
            "environment=$Environment",
            "location=$Location",
            "deployStorage=$($DeployStorage.ToString().ToLower())",
            "deploySqlServer=$($DeploySqlServer.ToString().ToLower())",
            "deployKeyVault=$($DeployKeyVault.ToString().ToLower())",
            "deployCosmosDb=$($DeployCosmosDb.ToString().ToLower())"
        )

        if ($DeploySqlServer) {
            $deployArgs += @(
                "sqlAadAdminObjectId=$SqlAadAdminObjectId",
                "sqlAadAdminLogin=$SqlAadAdminLogin",
                "sqlAadAdminPrincipalType=$SqlAadAdminPrincipalType"
            )
        }
    }

    # Execute deployment
    $result = & az @deployArgs 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage "Deployment failed"
        Write-Host $result -ForegroundColor Red
        exit 1
    }

    Write-Success "Deployment completed successfully"

    # Parse and display outputs
    $outputs = $result | ConvertFrom-Json
    if ($outputs.properties.outputs) {
        Write-Host ""
        Write-Host "Deployed Resources:" -ForegroundColor White
        $deployedResources = $outputs.properties.outputs.deployedResources.value
        foreach ($key in $deployedResources.PSObject.Properties.Name) {
            $value = $deployedResources.$key
            if ($value -ne "not deployed") {
                Write-Host "  - $key : $value" -ForegroundColor Green
            }
        }
    }
}

# ============================================
# POLICY DEPLOYMENT (Optional)
# ============================================

if (-not $SkipPolicyDeployment) {
    Write-Header "Policy Deployment"

    $policyScript = Join-Path $PoliciesDir "Deploy-SfiPolicies.ps1"

    if (Test-Path $policyScript) {
        Write-Step "Deploying SFI compliance policies..."
        Write-Info "Policy Effect: $PolicyEffect"

        if ($PSCmdlet.ShouldProcess("Subscription $SubscriptionId", "Deploy SFI policies")) {
            & $policyScript -SubscriptionId $SubscriptionId -PolicyEffect $PolicyEffect -Location $Location
        }
    }
    else {
        Write-Info "Policy deployment script not found. Skipping policy deployment."
    }
}
else {
    Write-Info "Policy deployment skipped (use -SkipPolicyDeployment:$false to enable)"
}

# ============================================
# SUMMARY
# ============================================

Write-Header "Deployment Summary"

Write-Host ""
Write-Host "SFI Compliant Resources Deployed Successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Security Configuration Applied:" -ForegroundColor White
Write-Host "  - Storage Account: allowSharedKeyAccess = false" -ForegroundColor Gray
Write-Host "  - SQL Server: Azure AD Only Authentication = true" -ForegroundColor Gray
Write-Host "  - Key Vault: enableRbacAuthorization = true" -ForegroundColor Gray
Write-Host "  - Cosmos DB: disableLocalAuth = true" -ForegroundColor Gray
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Configure RBAC permissions for your resources" -ForegroundColor White
Write-Host "  2. Set up Private Endpoints for production workloads" -ForegroundColor White
Write-Host "  3. Verify compliance in Azure Policy portal" -ForegroundColor White
Write-Host ""
Write-Host "Azure Portal Links:" -ForegroundColor Gray
Write-Host "  Resource Group: https://portal.azure.com/#@/resource/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" -ForegroundColor Blue
Write-Host "  Policy Compliance: https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyMenuBlade/~/Compliance" -ForegroundColor Blue
Write-Host ""
