# ========================================
# 团队配置文件
# ========================================
# 请根据你们团队的实际情况修改此文件
# 此文件会被 New-DevEnvironment.ps1 读取
# ========================================

# 设置后保存，然后在 PowerShell 中执行:
# . .\team-config.ps1

# Azure 订阅 ID (必填)
$env:AZURE_SUBSCRIPTION_ID = "your-subscription-id-here"

# 默认区域 (可选，不设置则使用 eastus)
# $env:AZURE_DEFAULT_LOCATION = "eastus"

# SQL Server 管理员组 (如果经常需要创建 SQL Server)
# $env:SQL_ADMIN_GROUP_ID = "aad-group-object-id"
# $env:SQL_ADMIN_GROUP_NAME = "sql-admins@yourcompany.com"

# ========================================
# 团队成员别名 (用于资源命名)
# ========================================
# 建议使用 2-8 位小写字母+数字
# 例如: zhangsan -> zs, lisi -> ls, wangwu -> ww
#
# 使用时: .\New-DevEnvironment.ps1 -Developer zs
# 会创建: rg-dev-zs 资源组
# ========================================

Write-Host "团队配置已加载" -ForegroundColor Green
Write-Host "  Subscription: $env:AZURE_SUBSCRIPTION_ID" -ForegroundColor Gray
