# ========================================
# SFI 合规资源创建向导
# ========================================
# 交互式引导创建 Azure 资源
# 直接运行，无需任何参数
# ========================================

param(
    # 演练模式：走完整个流程，但不实际创建任何资源
    [Alias("WhatIf", "Demo")]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$script:IsDryRun = $DryRun

if ($DryRun) {
    $Host.UI.RawUI.WindowTitle = "Azure SFI 资源创建向导 [演练模式]"
} else {
    $Host.UI.RawUI.WindowTitle = "Azure SFI 资源创建向导"
}

# ============================================
# 配色和辅助函数
# ============================================

function Clear-Line {
    Write-Host "`r$(' ' * 80)`r" -NoNewline
}

function Write-Title {
    param([string]$Text)
    $width = 50
    $padding = [math]::Max(0, ($width - $Text.Length) / 2)
    Write-Host ""
    Write-Host ("=" * $width) -ForegroundColor Cyan
    Write-Host (" " * $padding + $Text) -ForegroundColor Cyan
    Write-Host ("=" * $width) -ForegroundColor Cyan
    if ($script:IsDryRun) {
        Write-Host ""
        Write-Host "  *** 演练模式 - 不会实际创建任何资源 ***" -ForegroundColor Magenta
    }
    Write-Host ""
}

function Write-Step {
    param([int]$Current, [int]$Total, [string]$Title)
    Write-Host ""
    Write-Host "  [$Current/$Total] " -ForegroundColor DarkGray -NoNewline
    Write-Host $Title -ForegroundColor Yellow
    Write-Host ("  " + "-" * 40) -ForegroundColor DarkGray
}

function Write-Option {
    param([string]$Key, [string]$Text, [switch]$Selected)
    if ($Selected) {
        Write-Host "  > " -ForegroundColor Green -NoNewline
        Write-Host "[$Key] $Text" -ForegroundColor White
    } else {
        Write-Host "    [$Key] $Text" -ForegroundColor Gray
    }
}

function Write-Info {
    param([string]$Text)
    Write-Host "  i " -ForegroundColor Blue -NoNewline
    Write-Host $Text -ForegroundColor Gray
}

function Write-Tip {
    param([string]$Text)
    Write-Host "  * " -ForegroundColor DarkYellow -NoNewline
    Write-Host $Text -ForegroundColor DarkGray
}

function Read-Input {
    param(
        [string]$Prompt,
        [string]$Default = "",
        [string]$Pattern = "",
        [string]$ErrorMessage = "输入格式不正确，请重试"
    )
    
    while ($true) {
        Write-Host ""
        if ($Default) {
            Write-Host "  $Prompt " -ForegroundColor White -NoNewline
            Write-Host "[$Default]" -ForegroundColor DarkGray -NoNewline
            Write-Host ": " -NoNewline
        } else {
            Write-Host "  ${Prompt}: " -ForegroundColor White -NoNewline
        }
        
        $input = Read-Host
        if ([string]::IsNullOrWhiteSpace($input) -and $Default) {
            return $Default
        }
        
        if ($Pattern -and $input -notmatch $Pattern) {
            Write-Host "  ! $ErrorMessage" -ForegroundColor Red
            continue
        }
        
        if (-not [string]::IsNullOrWhiteSpace($input)) {
            return $input
        }
        
        Write-Host "  ! 请输入有效内容" -ForegroundColor Red
    }
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$Default = 0
    )
    
    Write-Host ""
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $key = $i + 1
        if ($i -eq $Default) {
            Write-Host "  > " -ForegroundColor Green -NoNewline
            Write-Host "[$key] $($Options[$i])" -ForegroundColor White
        } else {
            Write-Host "    [$key] $($Options[$i])" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "  $Prompt " -ForegroundColor White -NoNewline
    Write-Host "[$($Default + 1)]" -ForegroundColor DarkGray -NoNewline
    Write-Host ": " -NoNewline
    
    $input = Read-Host
    if ([string]::IsNullOrWhiteSpace($input)) {
        return $Default
    }
    
    $choice = 0
    if ([int]::TryParse($input, [ref]$choice) -and $choice -ge 1 -and $choice -le $Options.Count) {
        return $choice - 1
    }
    
    return $Default
}

function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    
    $hint = if ($Default) { "[Y/n]" } else { "[y/N]" }
    Write-Host ""
    Write-Host "  $Prompt $hint " -ForegroundColor White -NoNewline
    $input = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($input)) {
        return $Default
    }
    
    return $input -match '^[yY]'
}

function Read-MultiSelect {
    param(
        [string]$Prompt,
        [hashtable[]]$Options  # @{Name=""; Description=""; Default=$true}
    )
    
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor White
    Write-Host "  (输入编号切换选择，直接回车确认)" -ForegroundColor DarkGray
    Write-Host ""
    
    $selected = @{}
    foreach ($opt in $Options) {
        $selected[$opt.Name] = $opt.Default
    }
    
    while ($true) {
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $opt = $Options[$i]
            $check = if ($selected[$opt.Name]) { "[x]" } else { "[ ]" }
            $color = if ($selected[$opt.Name]) { "Green" } else { "Gray" }
            Write-Host "    $($i + 1). " -ForegroundColor DarkGray -NoNewline
            Write-Host "$check " -ForegroundColor $color -NoNewline
            Write-Host "$($opt.Name)" -ForegroundColor White -NoNewline
            Write-Host " - $($opt.Description)" -ForegroundColor DarkGray
        }
        
        Write-Host ""
        Write-Host "  输入编号或回车确认: " -ForegroundColor White -NoNewline
        $input = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($input)) {
            break
        }
        
        $num = 0
        if ([int]::TryParse($input, [ref]$num) -and $num -ge 1 -and $num -le $Options.Count) {
            $name = $Options[$num - 1].Name
            $selected[$name] = -not $selected[$name]
        }
        
        # 清屏重绘选项
        for ($i = 0; $i -lt $Options.Count + 2; $i++) {
            Write-Host "`e[1A`e[2K" -NoNewline
        }
    }
    
    return $selected
}

# ============================================
# 主流程
# ============================================

Clear-Host
Write-Title "Azure SFI 合规资源创建向导"

Write-Host "  欢迎使用 SFI 合规资源创建向导！" -ForegroundColor White
Write-Host ""
Write-Host "  此工具将引导你创建符合安全标准的 Azure 资源：" -ForegroundColor Gray
Write-Host "    - Storage Account (禁用共享密钥)" -ForegroundColor DarkGray
Write-Host "    - Key Vault (启用 RBAC)" -ForegroundColor DarkGray
Write-Host "    - SQL Server (仅 AAD 认证)" -ForegroundColor DarkGray
Write-Host "    - Cosmos DB (禁用本地认证)" -ForegroundColor DarkGray
Write-Host ""

if (-not (Read-YesNo "准备好开始了吗?")) {
    Write-Host ""
    Write-Host "  已取消，下次再见！" -ForegroundColor Gray
    exit 0
}

$totalSteps = 7
$config = @{}

# ============================================
# Step 1: Azure 登录检查
# ============================================

Write-Step -Current 1 -Total $totalSteps -Title "Azure 登录检查"

if ($script:IsDryRun) {
    Write-Host "  [演练] 跳过 Azure 登录检查" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  √ 模拟登录: " -ForegroundColor Green -NoNewline
    Write-Host "demo-user@example.com" -ForegroundColor White
    $account = @{ user = @{ name = "demo-user@example.com" } }
} else {
    Write-Host "  正在检查 Azure 登录状态..." -ForegroundColor Gray

    $account = az account show 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

    if (-not $account) {
        Write-Host ""
        Write-Host "  ! 未登录 Azure，正在打开登录页面..." -ForegroundColor Yellow
        az login | Out-Null
        $account = az account show 2>&1 | ConvertFrom-Json
    }

    Write-Host ""
    Write-Host "  √ 已登录: " -ForegroundColor Green -NoNewline
    Write-Host $account.user.name -ForegroundColor White
}

# ============================================
# Step 2: 选择订阅
# ============================================

Write-Step -Current 2 -Total $totalSteps -Title "选择 Azure 订阅"

if ($script:IsDryRun) {
    # 演练模式：使用模拟订阅
    $subscriptions = @(
        @{ id = "00000000-0000-0000-0000-000000000001"; name = "Dev Subscription (模拟)"; isDefault = $true }
        @{ id = "00000000-0000-0000-0000-000000000002"; name = "Prod Subscription (模拟)"; isDefault = $false }
    )
} else {
    $subscriptions = az account list --query "[?state=='Enabled']" | ConvertFrom-Json
}

$subNames = $subscriptions | ForEach-Object { "$($_.name) ($($_.id.Substring(0,8))...)" }

$defaultIdx = 0
for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    if ($subscriptions[$i].isDefault) {
        $defaultIdx = $i
        break
    }
}

$subChoice = Read-Choice -Prompt "选择订阅" -Options $subNames -Default $defaultIdx
$config.SubscriptionId = $subscriptions[$subChoice].id
$config.SubscriptionName = $subscriptions[$subChoice].name

if (-not $script:IsDryRun) {
    az account set --subscription $config.SubscriptionId | Out-Null
}
Write-Host ""
Write-Host "  √ 已选择: $($config.SubscriptionName)" -ForegroundColor Green

# ============================================
# Step 3: 开发者信息
# ============================================

Write-Step -Current 3 -Total $totalSteps -Title "开发者信息"

Write-Tip "用于资源命名，避免与他人冲突"

$config.Developer = Read-Input `
    -Prompt "你的别名 (2-8位小写字母数字，如: zhangsan=zs)" `
    -Pattern "^[a-z0-9]{2,8}$" `
    -ErrorMessage "请输入 2-8 位小写字母或数字"

# 生成资源组名
$config.ResourceGroupName = "rg-dev-$($config.Developer)"
$config.ProjectName = $config.Developer

Write-Host ""
Write-Host "  √ 资源组名称: " -ForegroundColor Green -NoNewline
Write-Host $config.ResourceGroupName -ForegroundColor White

# ============================================
# Step 4: 选择资源
# ============================================

Write-Step -Current 4 -Total $totalSteps -Title "选择要创建的资源"

$resourceOptions = @(
    @{ Name = "Storage Account"; Description = "Blob/Queue/Table 存储"; Default = $true }
    @{ Name = "Key Vault"; Description = "密钥和证书管理"; Default = $true }
    @{ Name = "SQL Server"; Description = "关系型数据库"; Default = $false }
    @{ Name = "Cosmos DB"; Description = "NoSQL 数据库"; Default = $false }
)

$selectedResources = Read-MultiSelect -Prompt "选择需要的资源:" -Options $resourceOptions

$config.DeployStorage = $selectedResources["Storage Account"]
$config.DeployKeyVault = $selectedResources["Key Vault"]
$config.DeploySql = $selectedResources["SQL Server"]
$config.DeployCosmos = $selectedResources["Cosmos DB"]

# 如果选择了 SQL，需要 AAD 管理员信息
if ($config.DeploySql) {
    Write-Host ""
    Write-Host "  SQL Server 需要配置 Azure AD 管理员" -ForegroundColor Yellow
    
    $config.SqlAdminLogin = Read-Input -Prompt "AAD 管理员邮箱/组名"
    $config.SqlAdminObjectId = Read-Input `
        -Prompt "AAD 对象 ID (GUID)" `
        -Pattern "^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$" `
        -ErrorMessage "请输入有效的 GUID 格式"
}

# ============================================
# Step 5: 网络安全边界 (NSP) 配置
# ============================================

Write-Step -Current 5 -Total $totalSteps -Title "网络安全边界 (NSP) 配置"

Write-Info "NSP 可为 PaaS 资源提供网络隔离，防止未授权访问"
Write-Tip "建议生产环境启用 NSP"

$config.DeployNsp = Read-YesNo "是否启用 Network Security Perimeter?" -Default $false

if ($config.DeployNsp) {
    Write-Host ""
    Write-Host "  NSP 访问模式:" -ForegroundColor Yellow
    $nspModeOptions = @(
        "Learning (监控模式 - 记录但不阻止)"
        "Enforced (强制模式 - 阻止非合规流量)"
    )
    $modeChoice = Read-Choice -Prompt "选择 NSP 模式" -Options $nspModeOptions -Default 0
    $config.NspAccessMode = if ($modeChoice -eq 0) { "Learning" } else { "Enforced" }
    
    Write-Host ""
    Write-Host "  √ NSP 模式: $($config.NspAccessMode)" -ForegroundColor Green
} else {
    $config.NspAccessMode = "Learning"
    Write-Host ""
    Write-Host "  √ 跳过 NSP 配置" -ForegroundColor Gray
}

# ============================================
# Step 6: 选择区域
# ============================================

Write-Step -Current 6 -Total $totalSteps -Title "选择部署区域"

if ($script:IsDryRun) {
    # 演练模式：使用模拟区域列表
    $regions = @(
        @{ name = "eastus"; displayName = "East US" }
        @{ name = "westus2"; displayName = "West US 2" }
        @{ name = "westeurope"; displayName = "West Europe" }
        @{ name = "southeastasia"; displayName = "Southeast Asia" }
    )
    Write-Host "  [演练] 使用模拟区域列表" -ForegroundColor Magenta
} else {
    # 正式模式：从 Azure 动态加载区域
    Write-Host "  正在加载可用区域..." -ForegroundColor Gray
    $regions = az account list-locations --query "[?metadata.regionType=='Physical'].{name:name, displayName:displayName}" -o json 2>&1 | ConvertFrom-Json
    
    if (-not $regions -or $regions.Count -eq 0) {
        Write-Host "  ! 无法加载区域列表，使用默认列表" -ForegroundColor Yellow
        $regions = @(
            @{ name = "eastus"; displayName = "East US" }
            @{ name = "westus2"; displayName = "West US 2" }
            @{ name = "westeurope"; displayName = "West Europe" }
            @{ name = "southeastasia"; displayName = "Southeast Asia" }
        )
    }
    Write-Host "`e[1A`e[2K" -NoNewline  # 清除加载提示
}

# 常用区域优先显示
$preferredRegions = @("eastus", "westus2", "westeurope", "southeastasia", "eastasia", "japaneast", "australiaeast", "uksouth", "centralus", "northeurope")
$sortedRegions = @()

# 先添加常用区域
foreach ($pr in $preferredRegions) {
    $match = $regions | Where-Object { $_.name -eq $pr }
    if ($match) { $sortedRegions += $match }
}

# 再添加其他区域（按名称排序）
$otherRegions = $regions | Where-Object { $_.name -notin $preferredRegions } | Sort-Object displayName
$sortedRegions += $otherRegions

# 限制显示数量，避免列表太长
$displayRegions = $sortedRegions | Select-Object -First 15
$regionNames = $displayRegions | ForEach-Object { "$($_.name) - $($_.displayName)" }

$regionChoice = Read-Choice -Prompt "选择区域 (显示前15个常用区域)" -Options $regionNames -Default 0
$config.Location = $displayRegions[$regionChoice].name

# 默认过期时间：7天
$config.AutoDeleteAfterDays = 7
$deleteAfterDate = (Get-Date).AddDays(7).ToString("yyyy-MM-dd")

# ============================================
# Step 7: 确认并部署
# ============================================

Write-Step -Current 7 -Total $totalSteps -Title "确认配置"

Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────┐" -ForegroundColor DarkGray
Write-Host "  │ 配置摘要                                    │" -ForegroundColor DarkGray
Write-Host "  ├─────────────────────────────────────────────┤" -ForegroundColor DarkGray
Write-Host "  │ 订阅:       " -ForegroundColor DarkGray -NoNewline
Write-Host ("{0,-32}" -f $config.SubscriptionName.Substring(0, [Math]::Min(30, $config.SubscriptionName.Length))) -ForegroundColor White -NoNewline
Write-Host "│" -ForegroundColor DarkGray
Write-Host "  │ 资源组:     " -ForegroundColor DarkGray -NoNewline
Write-Host ("{0,-32}" -f $config.ResourceGroupName) -ForegroundColor Cyan -NoNewline
Write-Host "│" -ForegroundColor DarkGray
Write-Host "  │ 区域:       " -ForegroundColor DarkGray -NoNewline
Write-Host ("{0,-32}" -f $config.Location) -ForegroundColor White -NoNewline
Write-Host "│" -ForegroundColor DarkGray
Write-Host "  │ 过期时间:   " -ForegroundColor DarkGray -NoNewline
Write-Host ("{0,-32}" -f $deleteAfterDate) -ForegroundColor Yellow -NoNewline
Write-Host "│" -ForegroundColor DarkGray
if ($config.DeployNsp) {
    Write-Host "  │ NSP 模式:   " -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-32}" -f $config.NspAccessMode) -ForegroundColor Magenta -NoNewline
    Write-Host "│" -ForegroundColor DarkGray
}
Write-Host "  ├─────────────────────────────────────────────┤" -ForegroundColor DarkGray
Write-Host "  │ 资源:                                       │" -ForegroundColor DarkGray
$resourceList = @()
if ($config.DeployStorage) { $resourceList += "Storage Account" }
if ($config.DeployKeyVault) { $resourceList += "Key Vault" }
if ($config.DeploySql) { $resourceList += "SQL Server" }
if ($config.DeployCosmos) { $resourceList += "Cosmos DB" }
if ($config.DeployNsp) { $resourceList += "Network Security Perimeter" }
foreach ($r in $resourceList) {
    Write-Host "  │   [x] " -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-37}" -f $r) -ForegroundColor Green -NoNewline
    Write-Host "│" -ForegroundColor DarkGray
}
Write-Host "  └─────────────────────────────────────────────┘" -ForegroundColor DarkGray

if (-not (Read-YesNo "确认创建以上资源?")) {
    Write-Host ""
    Write-Host "  已取消" -ForegroundColor Gray
    exit 0
}

# ============================================
# 执行部署
# ============================================

# 获取脚本目录
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = if ($ScriptDir) { Split-Path -Parent $ScriptDir } else { $PWD.Path }
$InfraDir = Join-Path $RootDir "infra"

# 生成资源名称预览
$storageAccountName = ($config.ProjectName + "dev").ToLower() -replace '[^a-z0-9]', ''
$storageAccountName = "st" + $storageAccountName.Substring(0, [Math]::Min(22, $storageAccountName.Length))
$keyVaultName = "kv-$($config.ProjectName)-dev".Substring(0, [Math]::Min(24, "kv-$($config.ProjectName)-dev".Length))
$sqlServerName = "sql-$($config.ProjectName)-dev"
$cosmosDbName = "cosmos-$($config.ProjectName)-dev"

if ($script:IsDryRun) {
    # ============================================
    # 演练模式 - 模拟部署
    # ============================================
    
    Write-Host ""
    Write-Host "  [演练] 模拟创建资源..." -ForegroundColor Magenta
    Write-Host ""
    
    Write-Host "  [1/2] 创建资源组..." -ForegroundColor Gray
    Start-Sleep -Milliseconds 500
    Write-Host "  √ [演练] 资源组: $($config.ResourceGroupName)" -ForegroundColor Magenta
    
    Write-Host "  [2/2] 部署资源..." -ForegroundColor Gray
    Start-Sleep -Milliseconds 800
    Write-Host "  √ [演练] 部署完成" -ForegroundColor Magenta
    
    # 模拟输出
    $simulatedResources = @{}
    if ($config.DeployStorage) { $simulatedResources["storageAccountName"] = $storageAccountName }
    if ($config.DeployKeyVault) { $simulatedResources["keyVaultName"] = $keyVaultName }
    if ($config.DeploySql) { $simulatedResources["sqlServerName"] = $sqlServerName }
    if ($config.DeployCosmos) { $simulatedResources["cosmosDbAccountName"] = $cosmosDbName }
    if ($config.DeployNsp) { $simulatedResources["nspName"] = "nsp-$($config.ProjectName)-dev" }
    
} else {
    # ============================================
    # 正式部署
    # ============================================
    
    Write-Host ""
    Write-Host "  正在创建资源，请稍候..." -ForegroundColor Yellow
    Write-Host ""

    # 创建资源组
    Write-Host "  [1/2] 创建资源组..." -ForegroundColor Gray
    $tags = @(
        "Developer=$($config.Developer)",
        "Feature=$(if ($config.Feature) { $config.Feature } else { 'general' })",
        "DeleteAfter=$deleteAfterDate",
        "CreatedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        "SecurityCompliance=SFI-ID4.2.1"
    )

    az group create `
        --name $config.ResourceGroupName `
        --location $config.Location `
        --tags $tags `
        --output none 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ! 资源组创建失败" -ForegroundColor Red
        exit 1
    }

    Write-Host "  √ 资源组已创建" -ForegroundColor Green

    # 部署 Bicep
    Write-Host "  [2/2] 部署资源..." -ForegroundColor Gray

    $deployParams = @(
        "projectName=$($config.ProjectName)",
        "environment=dev",
        "location=$($config.Location)",
        "deployStorage=$($config.DeployStorage.ToString().ToLower())",
        "deployKeyVault=$($config.DeployKeyVault.ToString().ToLower())",
        "deploySqlServer=$($config.DeploySql.ToString().ToLower())",
        "deployCosmosDb=$($config.DeployCosmos.ToString().ToLower())",
        "deployNsp=$($config.DeployNsp.ToString().ToLower())"
    )

    if ($config.DeployNsp) {
        $deployParams += "nspAccessMode=$($config.NspAccessMode)"
    }

    if ($config.DeploySql) {
        $deployParams += "sqlAadAdminObjectId=$($config.SqlAdminObjectId)"
        $deployParams += "sqlAadAdminLogin=$($config.SqlAdminLogin)"
        $deployParams += "sqlAadAdminPrincipalType=Group"
    }

    $result = az deployment group create `
        --resource-group $config.ResourceGroupName `
        --template-file "$InfraDir\main.bicep" `
        --parameters $deployParams `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  ! 部署失败" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
        exit 1
    }
}

# ============================================
# 完成
# ============================================

Clear-Host

if ($script:IsDryRun) {
    Write-Title "演练完成!"
    Write-Host "  这是一次演练，没有创建任何资源" -ForegroundColor Magenta
} else {
    Write-Title "创建完成!"
    Write-Host "  恭喜！你的开发环境已准备就绪" -ForegroundColor Green
}
Write-Host ""

# 显示资源列表
Write-Host "  将创建的资源:" -ForegroundColor White
Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray

if ($script:IsDryRun) {
    # 演练模式显示模拟资源
    foreach ($key in $simulatedResources.Keys) {
        Write-Host "    $key : " -ForegroundColor Gray -NoNewline
        Write-Host $simulatedResources[$key] -ForegroundColor Cyan
    }
} else {
    # 正式模式解析输出
    $outputs = $result | ConvertFrom-Json
    if ($outputs.properties.outputs.deployedResources) {
        $resources = $outputs.properties.outputs.deployedResources.value
        foreach ($prop in $resources.PSObject.Properties) {
            if ($prop.Value -ne "not deployed") {
                Write-Host "    $($prop.Name): " -ForegroundColor Gray -NoNewline
                Write-Host $prop.Value -ForegroundColor Cyan
            }
        }
    }
}

Write-Host ""
Write-Host "  资源组: " -ForegroundColor Yellow -NoNewline
Write-Host $config.ResourceGroupName -ForegroundColor Cyan
Write-Host "  区域:   " -ForegroundColor Yellow -NoNewline
Write-Host $config.Location -ForegroundColor White
Write-Host "  订阅:   " -ForegroundColor Yellow -NoNewline
Write-Host $config.SubscriptionName -ForegroundColor White

Write-Host ""
Write-Host "  安全配置 (SFI-ID4.2.1):" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
if ($config.DeployStorage) { Write-Host "    Storage:  allowSharedKeyAccess = false" -ForegroundColor DarkGreen }
if ($config.DeployKeyVault) { Write-Host "    KeyVault: enableRbacAuthorization = true" -ForegroundColor DarkGreen }
if ($config.DeploySql) { Write-Host "    SQL:      azureADOnlyAuthentication = true" -ForegroundColor DarkGreen }
if ($config.DeployCosmos) { Write-Host "    Cosmos:   disableLocalAuth = true" -ForegroundColor DarkGreen }
if ($config.DeployNsp) { 
    Write-Host "    NSP:      accessMode = $($config.NspAccessMode)" -ForegroundColor DarkGreen 
    Write-Host "              (资源已关联到网络安全边界)" -ForegroundColor DarkGray
}

Write-Host ""
if ($config.AutoDeleteAfterDays -gt 0) {
    Write-Host "  过期时间: " -ForegroundColor Gray -NoNewline
    Write-Host $deleteAfterDate -ForegroundColor Yellow
}

if ($script:IsDryRun) {
    Write-Host ""
    Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  要真正创建资源，请运行:" -ForegroundColor White
    Write-Host "  .\Start.ps1" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "  快速访问:" -ForegroundColor Yellow
    Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  https://portal.azure.com/#@/resource/subscriptions/$($config.SubscriptionId)/resourceGroups/$($config.ResourceGroupName)" -ForegroundColor Blue
    Write-Host ""
}

Write-Host "  按任意键退出..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
