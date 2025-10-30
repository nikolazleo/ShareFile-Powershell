# ShareFile PowerShell Utilities

PowerShell utilities for managing ShareFile user accounts, including finding and removing disabled users with proper item and group reassignment.

## Table of Contents

- [Prerequisites](#prerequisites)
- [ShareFile Module Installation](#sharefile-module-installation)
- [ShareFile Authentication Setup](#sharefile-authentication-setup)
- [Usage](#usage)
- [Scripts Overview](#scripts-overview)
- [Safety Features](#safety-features)
- [Troubleshooting](#troubleshooting)
- [Examples](#examples)

## Prerequisites

- **PowerShell 5.1 or later** (Windows PowerShell or PowerShell Core)
- **ShareFile PowerShell Snapin** (installation instructions below)
- **ShareFile account** with administrative privileges
- **ShareFile API access** (OAuth2 application credentials)

## ShareFile Module Installation

### Step 1: Download ShareFile PowerShell Snapin

1. Visit the [ShareFile Developer Portal](https://api.sharefile.com/rest/docs/powershell.aspx)
2. Download the ShareFile PowerShell Snapin installer
3. Run the installer as Administrator
4. Follow the installation wizard prompts

### Step 2: Verify Installation

Open PowerShell as Administrator and verify the snapin is available:

```powershell
# Check if ShareFile snapin is available
Get-PSSnapin -Registered | Where-Object { $_.Name -like "*ShareFile*" }

# Add the ShareFile snapin to current session
Add-PSSnapin ShareFile

# Verify ShareFile cmdlets are available
Get-Command -Module ShareFile | Select-Object Name, CommandType
```

### Alternative Installation (if available via PowerShell Gallery)

```powershell
# Install from PowerShell Gallery (if available)
Install-Module -Name ShareFile -Scope AllUsers -Force

# Import the module
Import-Module ShareFile
```

## ShareFile Authentication Setup

### Step 1: Create ShareFile API Application

1. Log in to your ShareFile account as an administrator
2. Navigate to **Admin Settings** → **API & SSO** → **API Applications**
3. Click **Add Application**
4. Choose **OAuth2** application type
5. Note down the following credentials:
   - **Client ID**
   - **Client Secret**
   - **Subdomain** (your ShareFile subdomain)

### Step 2: Initial Authentication and Client Configuration

Create your first ShareFile client configuration:

```powershell
# Add ShareFile snapin
Add-PSSnapin ShareFile

# Create new ShareFile client (interactive authentication)
$clientConfig = New-SfClient -Name "c:\tmp\sfclient.sfps"
```

This will:

1. Prompt for your ShareFile credentials
2. Handle OAuth2 authentication flow
3. Save authentication tokens to the specified `.sfps` file
4. Allow future script runs without re-authentication

### Step 3: Test Authentication

```powershell
# Test the saved client configuration
$client = Get-SfClient -Name "c:\tmp\sfclient.sfps"

# Test API access by listing account information
$accountInfo = Send-SfRequest -Client $client -Entity Accounts
Write-Host "Connected to ShareFile account: $($accountInfo.Name)"
```

### Authentication File Security

**Important**: The `.sfps` file contains authentication tokens. Protect it appropriately:

- Store in a secure location (default: `c:\tmp\sfclient.sfps`)
- Restrict file permissions to authorized users only
- Consider using service accounts for automated scenarios
- Tokens may expire and require re-authentication

## Usage

### Primary Script: Remove-DisabledShareFileUsers.ps1

This script combines user discovery and deletion in a single, safe operation.

#### Basic Usage

```powershell
# Basic usage - finds and removes disabled users
.\Remove-DisabledShareFileUsers.ps1 -AdminUserId "admin@company.com"
```

#### Safe Testing

```powershell
# Test run - shows what would be deleted without actually deleting
.\Remove-DisabledShareFileUsers.ps1 -AdminUserId "admin@company.com" -WhatIf
```

#### Custom Configuration

```powershell
# Custom paths and verbose output
.\Remove-DisabledShareFileUsers.ps1 `
    -AdminUserId "admin@company.com" `
    -ClientConfigPath "d:\secure\sfclient.sfps" `
    -TempDirectory "d:\temp\" `
    -Verbose
```

### Parameters

| Parameter          | Required | Default                | Description                                           |
| ------------------ | -------- | ---------------------- | ----------------------------------------------------- |
| `AdminUserId`      | Yes      | -                      | User ID or email of admin to receive reassigned items |
| `ClientConfigPath` | No       | `c:\tmp\sfclient.sfps` | Path to ShareFile client configuration file           |
| `TempDirectory`    | No       | `C:\tmp\`              | Directory for temporary CSV files                     |
| `WhatIf`           | No       | -                      | Preview mode - shows actions without executing        |
| `Verbose`          | No       | -                      | Detailed logging output                               |

## Scripts Overview

### Remove-DisabledShareFileUsers.ps1 (Recommended)

**Main combined utility** that follows PowerShell best practices:

✅ **Features:**

- Finds disabled users (employees and clients)
- Safely deletes users with confirmation prompts
- Reassigns items and groups to specified admin user
- Progress tracking and detailed logging
- WhatIf support for safe testing
- Comprehensive error handling

### Legacy Scripts

#### disabledUsers.ps1

- Original script for finding disabled users
- Exports results to CSV files
- Useful for reporting without deletion

#### deleteUsers.ps1

- Original script for user deletion
- Requires pre-existing CSV files
- Less safety features than main script

## Safety Features

### Confirmation Prompts

The main script includes multiple safety mechanisms:

- **High Impact Confirmation**: Requires explicit confirmation before deletion
- **WhatIf Support**: Preview mode shows planned actions without execution
- **Individual User Confirmation**: Prompts for each user deletion

### Data Preservation

- **Complete Reassignment**: All user items and group memberships transferred to admin
- **No Orphaned Data**: Ensures no user data is left without ownership
- **CSV Backup**: Temporary CSV files created before deletion

### Error Handling

- **Graceful Failures**: Individual user failures don't stop entire process
- **Detailed Logging**: Verbose output for troubleshooting
- **Progress Tracking**: Visual progress bars for long operations

## Troubleshooting

### Common Issues

#### 1. ShareFile Snapin Not Found

```
Error: The Windows PowerShell snap-in 'ShareFile' is not installed
```

**Solution**: Install the ShareFile PowerShell Snapin (see installation section)

#### 2. Authentication Expired

```
Error: Authentication failed or token expired
```

**Solution**: Re-create client configuration

```powershell
$client = New-SfClient -Name "c:\tmp\sfclient.sfps"
```

#### 3. Admin User ID Invalid

```
Error: Admin user not found or invalid
```

**Solution**: Verify admin user ID/email exists and has appropriate permissions

#### 4. Permission Denied

```
Error: Access denied or insufficient permissions
```

**Solution**: Ensure authenticated user has admin privileges in ShareFile

### Debug Mode

Enable verbose logging for troubleshooting:

```powershell
.\Remove-DisabledShareFileUsers.ps1 -AdminUserId "admin@company.com" -Verbose
```

### Testing Connectivity

```powershell
# Test ShareFile API connectivity
Add-PSSnapin ShareFile
$client = Get-SfClient -Name "c:\tmp\sfclient.sfps"
$employees = Send-SfRequest -Client $client -Entity Accounts/Employees
Write-Host "Successfully retrieved $($employees.Count) employees"
```

## Examples

### Example 1: First Time Setup and Usage

```powershell
# 1. Add ShareFile snapin
Add-PSSnapin ShareFile

# 2. Create initial authentication (interactive)
$client = New-SfClient -Name "c:\tmp\sfclient.sfps"

# 3. Test run to see what would be deleted
.\Remove-DisabledShareFileUsers.ps1 -AdminUserId "admin@company.com" -WhatIf

# 4. Execute actual deletion after reviewing
.\Remove-DisabledShareFileUsers.ps1 -AdminUserId "admin@company.com"
```

### Example 2: Automated Scheduled Task

```powershell
# Script for scheduled execution (after initial setup)
Add-PSSnapin ShareFile
Set-Location "C:\Scripts\ShareFile"

# Log output to file
.\Remove-DisabledShareFileUsers.ps1 `
    -AdminUserId "serviceaccount@company.com" `
    -Verbose `
    *> "C:\Logs\ShareFile_$(Get-Date -Format 'yyyyMMdd').log"
```

### Example 3: Custom Paths and Security

```powershell
# Using secure locations and custom admin
.\Remove-DisabledShareFileUsers.ps1 `
    -AdminUserId "john.admin@company.com" `
    -ClientConfigPath "D:\Secure\ShareFile\client.sfps" `
    -TempDirectory "D:\Temp\ShareFile\" `
    -Verbose
```

### Example 4: Report Only (Using Legacy Script)

```powershell
# Generate report without deletion
Add-PSSnapin ShareFile
.\disabledUsers.ps1

# Review generated CSV files
Import-Csv "C:\tmp\employee.csv" | Format-Table
Import-Csv "C:\tmp\client.csv" | Format-Table
```

## Security Considerations

- **Credential Storage**: Protect `.sfps` files with appropriate file permissions
- **Service Accounts**: Use dedicated service accounts for automation
- **Logging**: Monitor script execution and maintain audit trails
- **Testing**: Always test with `-WhatIf` before production runs
- **Backup**: Consider backing up user data before bulk deletions

## Support

For ShareFile API documentation and support:

- [ShareFile Developer Portal](https://api.sharefile.com/rest/)
- [ShareFile PowerShell Documentation](https://api.sharefile.com/rest/docs/powershell.aspx)
- [ShareFile Support](https://www.sharefile.com/support)

## License

This project is provided as-is for educational and administrative purposes. Use at your own risk and ensure compliance with your organization's policies.
