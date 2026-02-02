# Azure SFI Compliant Resource Creation Tool

A lightweight, interactive toolkit for creating **SFI-ID4.2.1 (Safe Secrets Standard)** compliant Azure resources.

一套轻量级、交互式的 Azure 资源创建工具，自动满足 **SFI-ID4.2.1 (Safe Secrets Standard)** 安全标准。

---

## 🤔 Why This Tool?

### The Problem

When manually creating Azure resources, it's easy to forget security settings like disabling key-based access. This tool ensures all resources are created with security best practices by default.

### Existing Solutions Are Too Heavy

| Tool | Target User | Files | Learning Curve |
|------|-------------|-------|----------------|
| [Azure Landing Zones (ALZ-Bicep)](https://github.com/Azure/ALZ-Bicep) | Enterprise Architects | 100+ | High |
| [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) | Platform Engineers | Complex | High |
| [PSRule.Rules.Azure](https://azure.github.io/PSRule.Rules.Azure/) | DevOps | N/A (validation only) | Medium |
| **This Tool** | **Developers** | **~20** | **Low** |

### This Tool's Approach

```powershell
.\Start.ps1   # That's it. Follow the wizard.
```

- ✅ **Interactive wizard** - No YAML editing, no parameter files
- ✅ **SFI compliant by default** - All resources pass security scans
- ✅ **Lightweight** - Only what developers need
- ✅ **Dry-run mode** - Preview without creating resources (`-WhatIf`)

---

## 🚀 Quick Start

```powershell
# Clone the repo
git clone https://github.com/yhl10000/AzureResourceCreatingTool.git
cd AzureResourceCreatingTool

# Run the interactive wizard
.\Start.ps1

# Or dry-run first
.\Start.ps1 -WhatIf
```

The wizard guides you through:
1. Azure login check
2. Select subscription
3. Enter your alias (for resource naming)
4. Select resources to create
5. Select region (dynamically loaded from Azure)
6. Confirm and deploy

---

## 📋 Features

| Feature | Description |
|---------|-------------|
| **Security Compliant** | All resources automatically meet SFI-ID4.2.1 |
| **Interactive Wizard** | No parameters to memorize |
| **Auto Expiry** | Dev environments expire in 7 days (avoids resource sprawl) |
| **One-Click Cleanup** | Identify and remove expired environments |
| **Policy Enforcement** | Optionally deploy Azure Policy to block non-compliant resources |
| **Dry-Run Mode** | Preview the entire flow without creating anything |

---

## 🔒 Security Configuration

All resources created by this tool automatically comply with these security standards:

| Resource | Key Setting | Effect |
|----------|-------------|--------|
| **Storage Account** | `allowSharedKeyAccess = false` | Disables shared key access |
| **Key Vault** | `enableRbacAuthorization = true` | Uses RBAC instead of access policies |
| **SQL Server** | `azureADOnlyAuthentication = true` | AAD-only authentication |
| **Cosmos DB** | `disableLocalAuth = true` | Disables local key authentication |

### Additional Security Settings

| Setting | Value | Applies To |
|---------|-------|------------|
| `minimumTlsVersion` | `TLS1_2` | All |
| `publicNetworkAccess` | `Disabled` | All |
| `enablePurgeProtection` | `true` | Key Vault |
| `allowBlobPublicAccess` | `false` | Storage |

---

## 🛠️ Usage Options

### Option 1: Interactive Wizard (Recommended)

```powershell
.\Start.ps1
```

### Option 2: Command Line (For Automation)

```powershell
# Create dev environment
.\scripts\New-DevEnvironment.ps1 -Developer zs

# List all environments
.\scripts\Get-DevEnvironments.ps1

# Cleanup expired environments
.\scripts\Remove-ExpiredEnvironments.ps1 -Force
```

### Option 3: Direct Bicep (Advanced)

```powershell
az deployment group create `
    --resource-group "rg-myproject-dev" `
    --template-file "infra/main.bicep" `
    --parameters "infra/main.parameters.dev.json"
```

---

## 📁 Project Structure

```
AzureResourceCreatingTool/
├── Start.ps1                       # ⭐ Interactive wizard entry point
├── team-config.ps1                 # Team configuration
├── QUICKSTART.md                   # Quick start guide
│
├── scripts/                        # Utility scripts
│   ├── New-DevEnvironment.ps1      # Quick create dev environment
│   ├── Get-DevEnvironments.ps1     # List all environments
│   ├── Remove-ExpiredEnvironments.ps1  # Cleanup expired
│   ├── Deploy.ps1                  # Full deployment script
│   └── Remediate-NonCompliantResources.ps1  # Fix non-compliant resources
│
├── infra/                          # Bicep infrastructure code
│   ├── main.bicep                  # Main orchestration
│   ├── main.parameters.dev.json    # Dev parameters
│   ├── main.parameters.prod.json   # Prod parameters
│   ├── bicepconfig.json            # Bicep config
│   └── modules/                    # Security-hardened modules
│       ├── secure-storage.bicep
│       ├── secure-keyvault.bicep
│       ├── secure-sql-server.bicep
│       └── secure-cosmosdb.bicep
│
└── policies/                       # Azure Policy
    ├── sfi-policy-assignments.bicep
    └── Deploy-SfiPolicies.ps1
```

---

## 📊 Environment Management

### View Environment Status

```powershell
.\scripts\Get-DevEnvironments.ps1
```

Example output:
```
Developer  Status      Days Left  Resource Group
---------  ------      ---------  --------------
zs         Active      5d         rg-dev-zs
ls         Expiring    1d         rg-dev-ls
ww         EXPIRED     2d overdue rg-dev-ww
```

### Cleanup Expired Environments

```powershell
# Preview what will be cleaned up
.\scripts\Remove-ExpiredEnvironments.ps1 -ListOnly

# Execute cleanup
.\scripts\Remove-ExpiredEnvironments.ps1 -Force
```

---

## 🛡️ Azure Policy Deployment (Optional)

Deploy subscription-level policies to prevent anyone from creating non-compliant resources:

```powershell
# Start with Audit mode
.\policies\Deploy-SfiPolicies.ps1 `
    -SubscriptionId "<your-subscription-id>" `
    -PolicyEffect "Audit"

# Switch to Deny mode after verification
.\policies\Deploy-SfiPolicies.ps1 `
    -SubscriptionId "<your-subscription-id>" `
    -PolicyEffect "Deny"
```

### Policy List

| Policy | Effect | Policy ID |
|--------|--------|-----------|
| Storage - Disable shared key | Deny | `8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54` |
| SQL - AAD only auth | Deny | `abda6d70-9778-44e7-84a8-06713e6db027` |
| Key Vault - Enable RBAC | Audit | `12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5` |
| Cosmos DB - Disable local auth | Deny | `5450f5bd-9c72-4390-a9c4-a7aba4edfdd2` |

---

## 🔧 Remediate Existing Non-Compliant Resources

If you have existing resources that are non-compliant:

```powershell
# Preview mode (no actual changes)
.\scripts\Remediate-NonCompliantResources.ps1 `
    -SubscriptionId "<subscription-id>" `
    -WhatIf

# Execute remediation
.\scripts\Remediate-NonCompliantResources.ps1 `
    -SubscriptionId "<subscription-id>"
```

---

## 📋 Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (v2.50+)
- [PowerShell](https://docs.microsoft.com/powershell/scripting/install/installing-powershell) (v7.0+ recommended)
- Azure subscription with Contributor + User Access Administrator permissions

### Verify Environment

```powershell
az --version          # Check Azure CLI
az bicep version      # Check Bicep
pwsh --version        # Check PowerShell
```

---

## ❓ FAQ

### Q: "Not logged in" error when running Start.ps1
**A:** The script will automatically open a browser for login. Just follow the prompts.

### Q: How do I access the created resources?
**A:** Since key-based access is disabled, you need to:
1. Use Azure AD authentication
2. Assign appropriate RBAC roles (e.g., Storage Blob Data Contributor)

### Q: How do I manually delete an environment?
```powershell
az group delete --name rg-dev-zs --yes
```

### Q: How do I extend the expiry time?
```powershell
az group update --name rg-dev-zs --tags DeleteAfter=2025-12-31
```

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📚 Related Resources

- [QUICKSTART.md](./QUICKSTART.md) - Detailed usage guide
- [Microsoft SFI](https://aka.ms/sfi) - Secure Future Initiative
- [Azure Policy Built-in Definitions](https://docs.microsoft.com/azure/governance/policy/samples/built-in-policies)
- [Bicep Best Practices](https://docs.microsoft.com/azure/azure-resource-manager/bicep/best-practices)

---

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.
