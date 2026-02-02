# ========================================
# List My Dev Environments
# ========================================
# 查看当前所有开发环境状态
# ========================================

[CmdletBinding()]
param(
    # 只显示我的环境
    [string]$Developer = "",

    # 输出格式
    [ValidateSet("Table", "Json", "Brief")]
    [string]$Format = "Table"
)

$Config = @{
    SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
    ResourceGroupPrefix = "rg-dev"
}

if (-not $Config.SubscriptionId) {
    Write-Host "[ERROR] 未配置 AZURE_SUBSCRIPTION_ID 环境变量" -ForegroundColor Red
    exit 1
}

az account set --subscription $Config.SubscriptionId | Out-Null

$allGroups = az group list --query "[?starts_with(name, '$($Config.ResourceGroupPrefix)-')]" | ConvertFrom-Json

if ($allGroups.Count -eq 0) {
    Write-Host "没有找到开发环境" -ForegroundColor Gray
    exit 0
}

$today = Get-Date
$environments = @()

foreach ($rg in $allGroups) {
    # 过滤指定开发者
    if ($Developer -and $rg.tags.Developer -ne $Developer) {
        continue
    }

    $deleteAfter = $rg.tags.DeleteAfter
    $status = "Active"
    $daysLeft = "-"

    if ($deleteAfter -and $deleteAfter -ne "never") {
        try {
            $deleteDate = [DateTime]::ParseExact($deleteAfter, "yyyy-MM-dd", $null)
            $diff = ($deleteDate - $today).Days
            if ($diff -lt 0) {
                $status = "EXPIRED"
                $daysLeft = "$([Math]::Abs($diff))d overdue"
            } else {
                $daysLeft = "${diff}d"
                if ($diff -le 1) { $status = "Expiring" }
            }
        } catch { }
    }

    $environments += [PSCustomObject]@{
        ResourceGroup = $rg.name
        Developer = $rg.tags.Developer
        Feature = $rg.tags.Feature
        Status = $status
        DaysLeft = $daysLeft
        DeleteAfter = $deleteAfter
        CreatedAt = $rg.tags.CreatedAt
        Location = $rg.location
    }
}

switch ($Format) {
    "Json" {
        $environments | ConvertTo-Json -Depth 3
    }
    "Brief" {
        Write-Host ""
        Write-Host "开发环境列表 (共 $($environments.Count) 个):" -ForegroundColor Cyan
        Write-Host ""
        foreach ($env in $environments) {
            $color = switch ($env.Status) {
                "EXPIRED" { "Red" }
                "Expiring" { "Yellow" }
                default { "White" }
            }
            $feature = if ($env.Feature -and $env.Feature -ne "general") { "/$($env.Feature)" } else { "" }
            Write-Host "  $($env.Developer)$feature  ->  $($env.ResourceGroup)  [$($env.DaysLeft)]" -ForegroundColor $color
        }
        Write-Host ""
    }
    default {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  开发环境列表" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        $environments | Sort-Object Developer, Feature | Format-Table -Property `
            @{L="Developer"; E={$_.Developer}; Width=10},
            @{L="Feature"; E={$_.Feature}; Width=12},
            @{L="Status"; E={$_.Status}; Width=10},
            @{L="Days Left"; E={$_.DaysLeft}; Width=12},
            @{L="Resource Group"; E={$_.ResourceGroup}; Width=30},
            @{L="Location"; E={$_.Location}; Width=15}
        
        Write-Host ""
        Write-Host "提示:" -ForegroundColor Gray
        Write-Host "  - 创建环境: .\New-DevEnvironment.ps1 -Developer <name>" -ForegroundColor Gray
        Write-Host "  - 清理过期:  .\Remove-ExpiredEnvironments.ps1" -ForegroundColor Gray
        Write-Host ""
    }
}
