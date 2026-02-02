# ========================================
# Quick Dev Environment Creator
# ========================================
# 一键创建开发/测试环境的简化脚本
# 专为频繁创建临时环境设计
# ========================================

[CmdletBinding()]
param(
    # 必填: 你的名字或别名 (用于资源命名，避免冲突)
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{2,8}$')]
    [Alias("Name", "Alias")]
    [string]$Developer,

    # 可选: 功能/分支名称 (如 feature1, bugfix, sprint5)
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z0-9]{0,10}$')]
    [string]$Feature = "",

    # 资源选择 (默认只创建 Storage 和 KeyVault)
    [switch]$IncludeSql,
    [switch]$IncludeCosmosDb,
    [switch]$StorageOnly,
    [switch]$KeyVaultOnly,

    # SQL Server AAD Admin (如果 -IncludeSql)
    [string]$SqlAdminGroupId = "",
    [string]$SqlAdminGroupName = "",

    # 环境配置
    [ValidateSet("eastus", "westus2", "westeurope", "southeastasia")]
    [string]$Location = "eastus",

    # 自动清理设置 (天数后自动删除，0=不自动删除)
    [ValidateRange(0, 30)]
    [int]$AutoDeleteAfterDays = 7,

    # 跳过确认
    [switch]$Force
)

# ============================================
# 配置 - 根据你们团队的实际情况修改
# ============================================

$Config = @{
    # 你们团队的订阅 ID
    SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
    
    # 资源组命名前缀
    ResourceGroupPrefix = "rg-dev"
    
    # 默认 Tags
    DefaultTags = @{
        Team = "YourTeam"           # 改成你们的团队名
        CostCenter = "Dev"          # 成本中心
        AutoDelete = "true"         # 标记为可自动清理
    }
}

# ============================================
# 内部函数
# ============================================

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$InfraDir = Join-Path $RootDir "infra"

function Write-Step { param([string]$Msg) Write-Host ">> $Msg" -ForegroundColor Yellow }
function Write-OK { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Info { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor Gray }

# ============================================
# 参数处理
# ============================================

# 生成环境名称
$envSuffix = if ($Feature) { "$Developer-$Feature" } else { $Developer }
$resourceGroupName = "$($Config.ResourceGroupPrefix)-$envSuffix"
$projectName = $envSuffix.Replace("-", "")

# 确定要部署的资源
$deployStorage = -not $KeyVaultOnly
$deployKeyVault = -not $StorageOnly
$deploySql = $IncludeSql
$deployCosmos = $IncludeCosmosDb

# 计算自动删除日期
$deleteAfterDate = if ($AutoDeleteAfterDays -gt 0) {
    (Get-Date).AddDays($AutoDeleteAfterDays).ToString("yyyy-MM-dd")
} else { "never" }

# ============================================
# 确认
# ============================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Dev Environment Quick Creator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "将创建以下环境:" -ForegroundColor White
Write-Host ""
Write-Host "  Resource Group:  $resourceGroupName" -ForegroundColor White
Write-Host "  Location:        $Location" -ForegroundColor White
Write-Host "  Auto-delete:     $deleteAfterDate" -ForegroundColor $(if ($AutoDeleteAfterDays -gt 0) { "Yellow" } else { "Gray" })
Write-Host ""
Write-Host "  Resources:" -ForegroundColor White
if ($deployStorage) { Write-Host "    [x] Storage Account (SFI compliant)" -ForegroundColor Green }
if ($deployKeyVault) { Write-Host "    [x] Key Vault (RBAC enabled)" -ForegroundColor Green }
if ($deploySql) { Write-Host "    [x] SQL Server (AAD-only)" -ForegroundColor Green }
if ($deployCosmos) { Write-Host "    [x] Cosmos DB (local auth disabled)" -ForegroundColor Green }
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "确认创建? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "已取消" -ForegroundColor Gray
        exit 0
    }
}

# ============================================
# 检查订阅配置
# ============================================

if (-not $Config.SubscriptionId) {
    Write-Host ""
    Write-Host "[ERROR] 未配置订阅 ID!" -ForegroundColor Red
    Write-Host ""
    Write-Host "请设置环境变量或修改脚本中的配置:" -ForegroundColor Yellow
    Write-Host '  $env:AZURE_SUBSCRIPTION_ID = "your-subscription-id"' -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# ============================================
# 执行部署
# ============================================

Write-Host ""
Write-Step "检查 Azure 登录状态..."
$account = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Info "正在登录 Azure..."
    az login
}
az account set --subscription $Config.SubscriptionId
Write-OK "已切换到订阅: $($Config.SubscriptionId)"

Write-Step "创建资源组: $resourceGroupName"
$tags = $Config.DefaultTags.Clone()
$tags["Developer"] = $Developer
$tags["Feature"] = if ($Feature) { $Feature } else { "general" }
$tags["DeleteAfter"] = $deleteAfterDate
$tags["CreatedAt"] = (Get-Date).ToString("yyyy-MM-dd HH:mm")

$tagString = ($tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "

az group create `
    --name $resourceGroupName `
    --location $Location `
    --tags $tagString `
    --output none

Write-OK "资源组已创建"

Write-Step "部署 SFI 合规资源..."
$deploymentName = "dev-$envSuffix-$(Get-Date -Format 'yyyyMMddHHmm')"

$params = @(
    "projectName=$projectName",
    "environment=dev",
    "location=$Location",
    "deployStorage=$($deployStorage.ToString().ToLower())",
    "deployKeyVault=$($deployKeyVault.ToString().ToLower())",
    "deploySqlServer=$($deploySql.ToString().ToLower())",
    "deployCosmosDb=$($deployCosmos.ToString().ToLower())"
)

if ($deploySql -and $SqlAdminGroupId -and $SqlAdminGroupName) {
    $params += "sqlAadAdminObjectId=$SqlAdminGroupId"
    $params += "sqlAadAdminLogin=$SqlAdminGroupName"
    $params += "sqlAadAdminPrincipalType=Group"
}

$result = az deployment group create `
    --resource-group $resourceGroupName `
    --template-file "$InfraDir\main.bicep" `
    --name $deploymentName `
    --parameters @params `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] 部署失败!" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit 1
}

# ============================================
# 输出结果
# ============================================

$outputs = $result | ConvertFrom-Json

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  环境创建成功!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# 解析并显示创建的资源
if ($outputs.properties.outputs.deployedResources) {
    $resources = $outputs.properties.outputs.deployedResources.value
    
    Write-Host "已创建资源:" -ForegroundColor White
    foreach ($prop in $resources.PSObject.Properties) {
        if ($prop.Value -ne "not deployed") {
            Write-Host "  - $($prop.Name): $($prop.Value)" -ForegroundColor Cyan
        }
    }
}

Write-Host ""
Write-Host "快速访问:" -ForegroundColor Yellow
Write-Host "  Portal: https://portal.azure.com/#@/resource/subscriptions/$($Config.SubscriptionId)/resourceGroups/$resourceGroupName" -ForegroundColor Blue
Write-Host ""

if ($AutoDeleteAfterDays -gt 0) {
    Write-Host "注意: 此环境将在 $deleteAfterDate 后被标记为可删除" -ForegroundColor Yellow
    Write-Host "      运行 .\Remove-ExpiredEnvironments.ps1 清理过期环境" -ForegroundColor Gray
}

Write-Host ""

# 输出环境信息供后续使用
$envInfo = @{
    ResourceGroup = $resourceGroupName
    SubscriptionId = $Config.SubscriptionId
    Developer = $Developer
    Feature = $Feature
    DeleteAfter = $deleteAfterDate
    CreatedAt = (Get-Date).ToString("o")
}

# 保存环境信息到本地文件 (可选)
$envFilePath = Join-Path $RootDir ".environments"
if (-not (Test-Path $envFilePath)) { New-Item -ItemType Directory -Path $envFilePath | Out-Null }
$envInfo | ConvertTo-Json | Out-File (Join-Path $envFilePath "$resourceGroupName.json") -Encoding UTF8

Write-Info "环境信息已保存到: .environments\$resourceGroupName.json"
