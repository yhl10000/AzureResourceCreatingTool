# Azure SFI Compliant Resource Creation Tool

一套用于创建符合 **SFI-ID4.2.1 (Safe Secrets Standard)** 安全标准的 Azure 资源工具包。

---

## 🚀 快速开始（推荐）

**只需一条命令，跟着向导走：**

```powershell
.\Start.ps1
```

向导会引导你完成：
1. Azure 登录检查
2. 选择订阅
3. 输入开发者别名
4. 选择要创建的资源
5. 选择部署区域
6. 设置自动过期时间
7. 确认并部署

**无需记住任何参数，全程交互式引导！**

---

## 📋 功能概览

| 功能 | 说明 |
|-----|------|
| **安全合规** | 所有资源自动满足 SFI-ID4.2.1 标准 |
| **交互式向导** | 无需记住参数，跟着提示走 |
| **自动过期** | 开发环境默认 7 天后过期，避免资源堆积 |
| **一键清理** | 自动识别并清理过期环境 |
| **策略强制** | 可选部署 Azure Policy 阻止不合规资源创建 |

---

## 🛠️ 使用方式

### 方式一：交互式向导（推荐新手）

```powershell
.\Start.ps1
```

### 方式二：命令行快速创建（推荐老手）

```powershell
# 创建开发环境
.\scripts\New-DevEnvironment.ps1 -Developer zs

# 带功能分支
.\scripts\New-DevEnvironment.ps1 -Developer zs -Feature api

# 查看所有环境
.\scripts\Get-DevEnvironments.ps1

# 清理过期环境
.\scripts\Remove-ExpiredEnvironments.ps1 -Force
```

### 方式三：直接使用 Bicep（高级用户）

```powershell
az deployment group create `
    --resource-group "rg-myproject-dev" `
    --template-file "infra/main.bicep" `
    --parameters "infra/main.parameters.dev.json"
```

---

## 📁 项目结构

```
AzureResourceCreatingTool/
├── Start.ps1                       # ⭐ 交互式向导入口
├── team-config.ps1                 # 团队配置文件
├── QUICKSTART.md                   # 快速上手指南
│
├── scripts/                        # 实用脚本
│   ├── New-DevEnvironment.ps1      # 快速创建开发环境
│   ├── Get-DevEnvironments.ps1     # 查看所有环境状态
│   ├── Remove-ExpiredEnvironments.ps1  # 清理过期环境
│   ├── Deploy.ps1                  # 完整部署脚本
│   └── Remediate-NonCompliantResources.ps1  # 修复不合规资源
│
├── infra/                          # Bicep 基础设施代码
│   ├── main.bicep                  # 主编排文件
│   ├── main.parameters.dev.json    # 开发环境参数
│   ├── main.parameters.prod.json   # 生产环境参数
│   ├── bicepconfig.json            # Bicep 配置
│   └── modules/                    # 安全模块
│       ├── secure-storage.bicep    # Storage Account
│       ├── secure-keyvault.bicep   # Key Vault
│       ├── secure-sql-server.bicep # SQL Server
│       └── secure-cosmosdb.bicep   # Cosmos DB
│
└── policies/                       # Azure Policy
    ├── sfi-policy-assignments.bicep
    └── Deploy-SfiPolicies.ps1
```

---

## 🔒 安全配置

所有通过此工具创建的资源自动满足以下安全标准：

| 资源类型 | 关键设置 | 说明 |
|---------|---------|------|
| **Storage Account** | `allowSharedKeyAccess = false` | 禁用共享密钥访问 |
| **Key Vault** | `enableRbacAuthorization = true` | 使用 RBAC 替代访问策略 |
| **SQL Server** | `azureADOnlyAuthentication = true` | 仅允许 AAD 认证 |
| **Cosmos DB** | `disableLocalAuth = true` | 禁用本地密钥认证 |

### 其他安全设置

| 设置 | 值 | 适用资源 |
|-----|-----|---------|
| `minimumTlsVersion` | `TLS1_2` | 全部 |
| `publicNetworkAccess` | `Disabled` | 全部 |
| `enablePurgeProtection` | `true` | Key Vault |
| `allowBlobPublicAccess` | `false` | Storage |

---

## 📊 环境管理

### 查看环境状态

```powershell
.\scripts\Get-DevEnvironments.ps1
```

输出示例：
```
Developer  Feature   Status      Days Left  Resource Group
---------  -------   ------      ---------  --------------
zs         general   Active      5d         rg-dev-zs
zs         api       Expiring    1d         rg-dev-zs-api
ls         general   EXPIRED     2d overdue rg-dev-ls
```

### 清理过期环境

```powershell
# 预览将被清理的环境
.\scripts\Remove-ExpiredEnvironments.ps1 -ListOnly

# 执行清理
.\scripts\Remove-ExpiredEnvironments.ps1 -Force
```

---

## 🛡️ Azure Policy 部署（可选）

在订阅级别部署策略，阻止任何人创建不合规资源：

```powershell
# 先用 Audit 模式测试
.\policies\Deploy-SfiPolicies.ps1 `
    -SubscriptionId "<your-subscription-id>" `
    -PolicyEffect "Audit"

# 确认无误后切换到 Deny 模式
.\policies\Deploy-SfiPolicies.ps1 `
    -SubscriptionId "<your-subscription-id>" `
    -PolicyEffect "Deny"
```

### 策略列表

| 策略 | Effect | Policy ID |
|-----|--------|-----------|
| Storage - 禁用共享密钥 | Deny | `8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54` |
| SQL - 仅 AAD 认证 | Deny | `abda6d70-9778-44e7-84a8-06713e6db027` |
| Key Vault - 启用 RBAC | Audit | `12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5` |
| Cosmos DB - 禁用本地认证 | Deny | `5450f5bd-9c72-4390-a9c4-a7aba4edfdd2` |

---

## 🔧 修复现有不合规资源

如果你有已经创建的不合规资源：

```powershell
# 预览模式（不实际修改）
.\scripts\Remediate-NonCompliantResources.ps1 `
    -SubscriptionId "<subscription-id>" `
    -WhatIf

# 执行修复
.\scripts\Remediate-NonCompliantResources.ps1 `
    -SubscriptionId "<subscription-id>"
```

---

## 📋 前置要求

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (v2.50+)
- [PowerShell](https://docs.microsoft.com/powershell/scripting/install/installing-powershell) (v7.0+ 推荐)
- Azure 订阅权限: Contributor + User Access Administrator

### 检查环境

```powershell
az --version          # 检查 Azure CLI
az bicep version      # 检查 Bicep
pwsh --version        # 检查 PowerShell
```

---

## ❓ 常见问题

### Q: 运行 Start.ps1 提示 "未登录"
**A:** 脚本会自动打开浏览器让你登录，按提示操作即可。

### Q: 创建的资源如何访问？
**A:** 由于禁用了密钥访问，需要：
1. 使用 Azure AD 身份认证
2. 配置相应的 RBAC 角色（如 Storage Blob Data Contributor）

### Q: 如何手动删除环境？
```powershell
az group delete --name rg-dev-zs --yes
```

### Q: 如何延长环境过期时间？
```powershell
az group update --name rg-dev-zs --tags DeleteAfter=2025-12-31
```

---

## 📚 相关文档

- [QUICKSTART.md](./QUICKSTART.md) - 详细使用指南
- [SFI 安全标准](https://aka.ms/sfi)
- [Azure Policy 内置定义](https://docs.microsoft.com/azure/governance/policy/samples/built-in-policies)
- [Bicep 最佳实践](https://docs.microsoft.com/azure/azure-resource-manager/bicep/best-practices)

---

## 📄 License

MIT License
