# 开发环境快速创建工具 - 最佳实践指南

## 一、首次使用设置

### 1. 配置团队订阅

编辑 `team-config.ps1`，设置你们的 Azure 订阅 ID：

```powershell
$env:AZURE_SUBSCRIPTION_ID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

然后在 PowerShell 中执行：

```powershell
. .\team-config.ps1
```

> **提示**：也可以把这行加到你的 PowerShell Profile 中，这样每次打开终端自动加载。

---

## 二、日常使用

### 创建开发环境（最常用）

```powershell
# 最简单的用法 - 只需要你的别名
.\scripts\New-DevEnvironment.ps1 -Developer zs

# 创建带功能分支名的环境
.\scripts\New-DevEnvironment.ps1 -Developer zs -Feature feat1

# 只创建 Storage
.\scripts\New-DevEnvironment.ps1 -Developer zs -StorageOnly

# 只创建 KeyVault
.\scripts\New-DevEnvironment.ps1 -Developer zs -KeyVaultOnly

# 包含 SQL Server（需要指定 AAD 管理员）
.\scripts\New-DevEnvironment.ps1 -Developer zs -IncludeSql `
    -SqlAdminGroupId "group-object-id" `
    -SqlAdminGroupName "sql-admins@company.com"

# 设置自动过期天数（默认7天）
.\scripts\New-DevEnvironment.ps1 -Developer zs -AutoDeleteAfterDays 3

# 跳过确认直接创建
.\scripts\New-DevEnvironment.ps1 -Developer zs -Force
```

### 查看所有环境

```powershell
# 查看所有开发环境
.\scripts\Get-DevEnvironments.ps1

# 只看我的环境
.\scripts\Get-DevEnvironments.ps1 -Developer zs

# 简洁模式
.\scripts\Get-DevEnvironments.ps1 -Format Brief

# JSON 输出（方便脚本处理）
.\scripts\Get-DevEnvironments.ps1 -Format Json
```

### 清理过期环境

```powershell
# 查看哪些环境已过期（不实际删除）
.\scripts\Remove-ExpiredEnvironments.ps1 -ListOnly

# 删除所有过期环境
.\scripts\Remove-ExpiredEnvironments.ps1 -Force

# 只删除我的过期环境
.\scripts\Remove-ExpiredEnvironments.ps1 -Developer zs
```

---

## 三、命名规范

| 你输入的 | 创建的资源组 | Storage 账户 | Key Vault |
|---------|------------|--------------|-----------|
| `-Developer zs` | rg-dev-zs | stzsdev... | kv-zs-dev |
| `-Developer zs -Feature api` | rg-dev-zs-api | stzsapidev... | kv-zsapi-dev |
| `-Developer lisi` | rg-dev-lisi | stlisidev... | kv-lisi-dev |

---

## 四、团队协作最佳实践

### 1. 别名规范
建议每个团队成员使用固定的 2-8 位别名：
- 张三 → `zs`
- 李四 → `ls`
- 王五 → `ww`

### 2. 功能分支环境
当需要为特定功能创建隔离环境时：
```powershell
.\scripts\New-DevEnvironment.ps1 -Developer zs -Feature auth
.\scripts\New-DevEnvironment.ps1 -Developer zs -Feature cache
```

### 3. 定期清理
建议每周运行一次清理脚本：
```powershell
.\scripts\Remove-ExpiredEnvironments.ps1 -ListOnly  # 先看看
.\scripts\Remove-ExpiredEnvironments.ps1 -Force     # 确认后清理
```

### 4. 成本控制
- 默认环境 7 天后过期
- 临时测试环境建议 `-AutoDeleteAfterDays 1`
- 需要长期保留的环境 `-AutoDeleteAfterDays 0`

---

## 五、安全保障

所有通过此工具创建的资源都自动满足 **SFI-ID4.2.1** 安全标准：

| 资源类型 | 安全设置 |
|---------|---------|
| Storage Account | `allowSharedKeyAccess = false` |
| Key Vault | `enableRbacAuthorization = true` |
| SQL Server | `azureADOnlyAuthentication = true` |
| Cosmos DB | `disableLocalAuth = true` |

**你不需要记住这些设置** - 工具会自动应用！

---

## 六、常见问题

### Q: 创建失败提示 "未配置订阅 ID"
**A:** 运行 `. .\team-config.ps1` 或设置环境变量：
```powershell
$env:AZURE_SUBSCRIPTION_ID = "your-subscription-id"
```

### Q: 如何手动删除环境？
**A:** 使用 Azure CLI：
```powershell
az group delete --name rg-dev-zs --yes
```

### Q: 如何访问创建的资源？
**A:** 脚本输出中有 Portal 链接，或者：
```powershell
az resource list --resource-group rg-dev-zs --output table
```

### Q: 我需要 SQL Server 但没有 AAD 管理员组怎么办？
**A:** 联系你们的 Azure 管理员创建一个 AAD 安全组，然后把组 ID 配置到 `team-config.ps1` 中。

---

## 七、脚本速查表

| 任务 | 命令 |
|-----|------|
| 创建环境 | `.\scripts\New-DevEnvironment.ps1 -Developer <别名>` |
| 查看环境 | `.\scripts\Get-DevEnvironments.ps1` |
| 清理过期 | `.\scripts\Remove-ExpiredEnvironments.ps1 -Force` |
| 部署策略 | `.\policies\Deploy-SfiPolicies.ps1 -SubscriptionId <id>` |
| 修复不合规 | `.\scripts\Remediate-NonCompliantResources.ps1 -SubscriptionId <id>` |
