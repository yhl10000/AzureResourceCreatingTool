# ========================================
# Remove Expired Dev Environments
# ========================================
# 清理过期的开发/测试环境
# 根据资源组的 DeleteAfter 标签自动识别
# ========================================

[CmdletBinding(SupportsShouldProcess)]
param(
    # 只显示会被删除的环境，不实际删除
    [switch]$ListOnly,

    # 删除指定开发者的所有环境
    [string]$Developer = "",

    # 强制删除 (跳过确认)
    [switch]$Force
)

# ============================================
# 配置
# ============================================

$Config = @{
    SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
    ResourceGroupPrefix = "rg-dev"
}

$ErrorActionPreference = "Stop"

function Write-Step { param([string]$Msg) Write-Host ">> $Msg" -ForegroundColor Yellow }
function Write-OK { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }

# ============================================
# 检查配置
# ============================================

if (-not $Config.SubscriptionId) {
    Write-Host "[ERROR] 未配置 AZURE_SUBSCRIPTION_ID 环境变量" -ForegroundColor Red
    exit 1
}

# ============================================
# 获取所有开发环境资源组
# ============================================

Write-Step "扫描开发环境资源组..."

az account set --subscription $Config.SubscriptionId | Out-Null

$allGroups = az group list --query "[?starts_with(name, '$($Config.ResourceGroupPrefix)-')]" | ConvertFrom-Json

if ($allGroups.Count -eq 0) {
    Write-Host "没有找到开发环境资源组" -ForegroundColor Gray
    exit 0
}

# ============================================
# 分析资源组
# ============================================

$today = Get-Date
$expired = @()
$active = @()

foreach ($rg in $allGroups) {
    $deleteAfter = $rg.tags.DeleteAfter
    $developer = $rg.tags.Developer
    $createdAt = $rg.tags.CreatedAt

    $info = [PSCustomObject]@{
        Name = $rg.name
        Developer = $developer
        CreatedAt = $createdAt
        DeleteAfter = $deleteAfter
        Location = $rg.location
        Status = "Active"
    }

    # 过滤指定开发者
    if ($Developer -and $developer -ne $Developer) {
        continue
    }

    # 判断是否过期
    if ($deleteAfter -and $deleteAfter -ne "never") {
        try {
            $deleteDate = [DateTime]::ParseExact($deleteAfter, "yyyy-MM-dd", $null)
            if ($today -gt $deleteDate) {
                $info.Status = "Expired"
                $expired += $info
            } else {
                $daysLeft = ($deleteDate - $today).Days
                $info.Status = "Active ($daysLeft days left)"
                $active += $info
            }
        } catch {
            $active += $info
        }
    } else {
        $info.Status = "No expiry"
        $active += $info
    }
}

# ============================================
# 显示结果
# ============================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  开发环境清理报告" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($active.Count -gt 0) {
    Write-Host "活跃环境 ($($active.Count)):" -ForegroundColor Green
    $active | Format-Table -Property Name, Developer, Status, CreatedAt -AutoSize
}

if ($expired.Count -gt 0) {
    Write-Host "已过期环境 ($($expired.Count)):" -ForegroundColor Red
    $expired | Format-Table -Property Name, Developer, DeleteAfter, CreatedAt -AutoSize
} else {
    Write-Host "没有过期的环境" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# ============================================
# 删除过期环境
# ============================================

if ($ListOnly) {
    Write-Host ""
    Write-Host "使用 -Force 参数删除这些过期环境" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
if (-not $Force) {
    $confirm = Read-Host "确认删除以上 $($expired.Count) 个过期环境? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "已取消" -ForegroundColor Gray
        exit 0
    }
}

Write-Host ""
foreach ($rg in $expired) {
    Write-Step "删除: $($rg.Name)"
    
    if ($PSCmdlet.ShouldProcess($rg.Name, "Delete resource group")) {
        az group delete --name $rg.Name --yes --no-wait
        Write-OK "已提交删除请求: $($rg.Name)"
    }
}

Write-Host ""
Write-Host "删除请求已提交，资源组将在后台异步删除" -ForegroundColor Green
Write-Host "使用 'az group list --query \"[?starts_with(name, 'rg-dev-')]\"' 查看状态" -ForegroundColor Gray
Write-Host ""

# 清理本地环境文件
$envFilePath = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) ".environments"
foreach ($rg in $expired) {
    $localFile = Join-Path $envFilePath "$($rg.Name).json"
    if (Test-Path $localFile) {
        Remove-Item $localFile -Force
    }
}
