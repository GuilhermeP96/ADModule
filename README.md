# ADModule

Microsoft signed DLL for the ActiveDirectory PowerShell module.

> **Enhanced by [@GuilhermeP96](https://github.com/GuilhermeP96)** - Added interactive tools, batch processing, and script manager.

## Overview

This is a backup of Microsoft's ActiveDirectory PowerShell module from Server 2016 with RSAT. The DLL allows you to enumerate Active Directory **without installing RSAT** and **without administrative privileges**.

### Original Paths
- DLL: `C:\Windows\Microsoft.NET\assembly\GAC_64\Microsoft.ActiveDirectory.Management`
- Module: `C:\Windows\System32\WindowsPowerShell\v1.0\Modules\ActiveDirectory\`

## Project Structure

```
ADModule/
├── ADModule.bat                              # Script Manager (main entry point)
├── Microsoft.ActiveDirectory.Management.dll  # Microsoft signed AD DLL
├── ActiveDirectory/                          # Full AD module files
│   └── ActiveDirectory.psd1
├── scripts/
│   ├── Get-ADUserInfo.ps1                    # AD user query tool
│   └── Import-ActiveDirectory.ps1            # Module loader
├── img/
└── README.md
```

## Quick Start

### Option 1: Script Manager (Recommended)
Double-click `ADModule.bat` to open the interactive menu:

```
=============================================
       ADModule - Script Manager
=============================================

  [1] Get-ADUserInfo - Query AD user attributes
  [2] Import-ActiveDirectory - Import AD module
  [0] Exit
```

### Option 2: Direct PowerShell Usage
```powershell
# Import the DLL
Import-Module .\Microsoft.ActiveDirectory.Management.dll -Verbose

# Import full module (for all cmdlets)
Import-Module .\ActiveDirectory\ActiveDirectory.psd1

# List available commands
Get-Command -Module ActiveDirectory
```

## Features

### Get-ADUserInfo.ps1
Interactive tool to query AD user information with multiple features:

#### Parameters
| Parameter | Description |
|-----------|-------------|
| `-SamAccountName` | User login/username to query |
| `-Domain` | AD domain (auto-detected if not specified) |
| `-NoMenu` | Skip interactive menus (direct mode) |
| `-AllFields` | Display all AD attributes |
| `-ExportCsv` | Export data to CSV file |
| `-ExportPhoto` | Export user's profile photo |
| `-BatchFile` | Input file with user list for batch processing |
| `-BatchOutput` | Output CSV path for batch processing |

#### Usage Examples

```powershell
# Interactive mode (recommended)
.\scripts\Get-ADUserInfo.ps1

# Query specific user
.\scripts\Get-ADUserInfo.ps1 -SamAccountName "john.doe" -NoMenu

# Show ALL fields (all attributes)
.\scripts\Get-ADUserInfo.ps1 -SamAccountName "john.doe" -AllFields

# Export to CSV
.\scripts\Get-ADUserInfo.ps1 -SamAccountName "john.doe" -ExportCsv "C:\temp\user.csv"

# Batch processing (multiple users)
.\scripts\Get-ADUserInfo.ps1 -BatchFile "C:\users.txt" -BatchOutput "C:\export.csv"

# Multi-domain support
.\scripts\Get-ADUserInfo.ps1 -Domain "domain1.local,domain2.corp"
```

#### Batch Processing
The batch mode accepts text files with users in any of these formats:
- One user per line
- Comma-separated: `user1,user2,user3`
- Semicolon-separated: `user1;user2;user3`

When running batch mode interactively, native Windows file dialogs are used (with CLI fallback if GUI is unavailable).

#### Output Formats
1. **Summary** - Main fields organized by category (Identification, Organization, Contact, Address, Account Status, AD Location, Groups)
2. **All Fields** - Complete dump of all AD attributes with expanded arrays
3. **CSV Export** - All data exported to CSV file
4. **Photo Export** - User's profile photo (thumbnailPhoto or jpegPhoto)

### Import-ActiveDirectory.ps1
Loads the AD module for manual PowerShell usage. Supports:
- Loading from DLL on disk
- Loading from embedded byte array (for download-execute cradles)

```powershell
# Load from script
.\scripts\Import-ActiveDirectory.ps1

# Or with custom DLL path
Import-ActiveDirectory -ActiveDirectoryModule "C:\path\to\dll"
```

## Benefits

- **No RSAT required** - Works without Remote Server Administration Tools
- **No admin privileges** - Run as standard user
- **Microsoft signed** - Very low AV detection
- **CLM compatible** - Works in PowerShell Constrained Language Mode
- **Auto domain detection** - Automatically finds your AD domain
- **Multi-domain support** - Query multiple domains
- **Batch processing** - Process hundreds of users at once
- **GUI file dialogs** - Native Windows dialogs with CLI fallback

## Screenshots

### ADModule Import
![ADModule](img/AD_Module.png?raw=true "ADModule")

### ADModule Array (Download-Execute)
![ADModule_Array](img/AD_Module_Array.png?raw=true "ADModule_Array")

### Constrained Language Mode
![ADModule in CLM](img/AD_Module_CLM.png?raw=true "ADModule in CLM")

## Credits

- **Original Author**: [Samrat Ashok](https://github.com/samratashok) ([@intikitten](https://twitter.com/intikitten))
- **Import-ActiveDirectory.ps1**: [@D1iv3](https://github.com/samratashok/ADModule/pull/1)
- **Enhanced Scripts & Tools**: [@GuilhermeP96](https://github.com/GuilhermeP96)

## Links

- **Original Repository**: https://github.com/samratashok/ADModule
- **Blog Post**: https://www.labofapenetrationtester.com/2018/10/domain-enumeration-from-PowerShell-CLM.html

## Changelog

### v2.0.0 (2026-01-06) - @GuilhermeP96
- Added `Get-ADUserInfo.ps1` - Interactive AD user query tool
- Added `ADModule.bat` - Script manager with menu system
- Reorganized project structure (scripts in `/scripts` folder)
- Features added:
  - Interactive menus for user selection and output format
  - Automatic domain detection (3 methods + manual fallback)
  - Multi-domain support
  - Batch processing with GUI file dialogs
  - All fields display (all attributes with array expansion)
  - CSV export functionality
  - Profile photo export (thumbnailPhoto/jpegPhoto)
  - UTF-8 encoding support
  - English localization

### v1.0.0 - Original
- Microsoft.ActiveDirectory.Management.dll
- Import-ActiveDirectory.ps1
- ActiveDirectory module files
