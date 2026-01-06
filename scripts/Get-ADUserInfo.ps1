#Requires -Version 5.0
<#
.SYNOPSIS
    Script to query Active Directory user attributes without administrative privileges.

.DESCRIPTION
    This script loads ADModule and queries user attributes in AD.
    Attempts to detect the domain automatically. If it fails, prompts the user.
    Presents an interactive menu to choose between local user or manual entry.

.PARAMETER SamAccountName
    The login/username of the user to query. If not specified, displays menu.

.PARAMETER Domain
    The domain to use. If not specified, attempts automatic detection.
    Can be a single domain or comma-separated list to try multiple.

.PARAMETER NoMenu
    Skips the menu and uses SamAccountName directly.

.PARAMETER AllFields
    Displays ALL AD fields without exception (all available attributes).

.PARAMETER ExportCsv
    Path to export data to CSV.

.PARAMETER ExportPhoto
    Path to export the user's profile photo (if exists).
    If not specified and photo exists, saves to %TEMP%.

.EXAMPLE
    .\Get-ADUserInfo.ps1
    Displays interactive menu to choose user.

.EXAMPLE
    .\Get-ADUserInfo.ps1 -SamAccountName USER123 -NoMenu
    Queries the user directly without displaying menu.

.EXAMPLE
    .\Get-ADUserInfo.ps1 -SamAccountName USER123 -AllFields
    Displays ALL user fields.

.EXAMPLE
    .\Get-ADUserInfo.ps1 -Domain "domain1.local,domain2.corp"
    Attempts to connect to specified domains (in order).

.EXAMPLE
    .\Get-ADUserInfo.ps1 -SamAccountName USER123 -ExportCsv "C:\temp\user.csv"
    Exports all data to CSV.

.EXAMPLE
    .\Get-ADUserInfo.ps1 -BatchFile "C:\temp\users.txt" -BatchOutput "C:\temp\all_users.csv"
    Batch queries users from a text file and exports all to CSV.

.EXAMPLE
    .\Get-ADUserInfo.ps1 -BatchFile "C:\temp\users.txt"
    Batch queries users from a text file (opens file dialog for output).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$SamAccountName,

    [Parameter(Mandatory = $false)]
    [string]$Domain,

    [Parameter(Mandatory = $false)]
    [switch]$NoMenu,

    [Parameter(Mandatory = $false)]
    [switch]$AllFields,

    [Parameter(Mandatory = $false)]
    [string]$ExportCsv,

    [Parameter(Mandatory = $false)]
    [string]$ExportPhoto,

    [Parameter(Mandatory = $false)]
    [string]$BatchFile,

    [Parameter(Mandatory = $false)]
    [string]$BatchOutput
)

# Function to check if GUI is available
function Test-GuiAvailable {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Function to show Open File dialog (GUI)
function Show-OpenFileDialog {
    param(
        [string]$Title = "Select File",
        [string]$Filter = "Text Files (*.txt)|*.txt|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*",
        [string]$InitialDirectory = [Environment]::GetFolderPath('Desktop')
    )
    
    $guiAvailable = Test-GuiAvailable
    
    if ($guiAvailable) {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = $Title
        $dialog.Filter = $Filter
        $dialog.InitialDirectory = $InitialDirectory
        $dialog.Multiselect = $false
        
        $result = $dialog.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        return $null
    }
    else {
        # CLI fallback
        Write-Host ""
        Write-Host "[!] GUI not available. Enter file path manually." -ForegroundColor Yellow
        Write-Host ""
        $filePath = Read-Host "Enter full path to input file (users list)"
        
        if ([string]::IsNullOrWhiteSpace($filePath)) {
            return $null
        }
        
        if (Test-Path $filePath) {
            return $filePath
        }
        else {
            Write-Host "[X] File not found: $filePath" -ForegroundColor Red
            return $null
        }
    }
}

# Function to show Save File dialog (GUI)
function Show-SaveFileDialog {
    param(
        [string]$Title = "Save File",
        [string]$Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*",
        [string]$InitialDirectory = [Environment]::GetFolderPath('Desktop'),
        [string]$DefaultFileName = "AD_Users_Export.csv"
    )
    
    $guiAvailable = Test-GuiAvailable
    
    if ($guiAvailable) {
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Title = $Title
        $dialog.Filter = $Filter
        $dialog.InitialDirectory = $InitialDirectory
        $dialog.FileName = $DefaultFileName
        $dialog.OverwritePrompt = $true
        
        $result = $dialog.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        return $null
    }
    else {
        # CLI fallback
        Write-Host ""
        Write-Host "[!] GUI not available. Enter file path manually." -ForegroundColor Yellow
        Write-Host "    Default: " -NoNewline -ForegroundColor DarkGray
        Write-Host $DefaultFileName -ForegroundColor Cyan
        Write-Host ""
        $filePath = Read-Host "Enter full path for output CSV (or press Enter for default in TEMP)"
        
        if ([string]::IsNullOrWhiteSpace($filePath)) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            return Join-Path $env:TEMP "AD_Users_Export_$timestamp.csv"
        }
        
        return $filePath
    }
}

# Function to read users from file
function Read-UsersFromFile {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "[X] File not found: $FilePath" -ForegroundColor Red
        return @()
    }
    
    $content = Get-Content $FilePath -Raw -Encoding UTF8
    $users = @()
    
    # Try to parse: comma-separated, semicolon-separated, or line-by-line
    if ($content -match ',') {
        # Comma-separated
        $users = $content -split '[,\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    }
    elseif ($content -match ';') {
        # Semicolon-separated
        $users = $content -split '[;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    }
    else {
        # Line-by-line
        $users = $content -split '[\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    }
    
    return $users
}

# Function to process batch users
function Process-BatchUsers {
    param(
        [array]$Users,
        [string]$OutputPath,
        [string]$TargetDomain
    )
    
    $results = @()
    $total = $Users.Count
    $current = 0
    $success = 0
    $failed = 0
    
    Write-Host ""
    Write-Host "============================================="  -ForegroundColor Cyan
    Write-Host "         BATCH PROCESSING USERS              " -ForegroundColor Cyan
    Write-Host "============================================="  -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[*] Total users to process: " -NoNewline -ForegroundColor Yellow
    Write-Host $total -ForegroundColor White
    Write-Host ""
    
    foreach ($userName in $Users) {
        $current++
        $percent = [math]::Round(($current / $total) * 100)
        
        Write-Host "[" -NoNewline -ForegroundColor DarkGray
        Write-Host "$current/$total" -NoNewline -ForegroundColor Cyan
        Write-Host "] " -NoNewline -ForegroundColor DarkGray
        Write-Host "Processing: " -NoNewline -ForegroundColor White
        Write-Host $userName -NoNewline -ForegroundColor Yellow
        Write-Host " ... " -NoNewline
        
        try {
            $user = Get-ADUser -Identity $userName -Server $TargetDomain -Properties * -ErrorAction Stop
            
            # Build export object
            $export = [ordered]@{}
            $user.PSObject.Properties | Where-Object { 
                $_.Name -notin @('PropertyNames', 'AddedProperties', 'RemovedProperties', 'ModifiedProperties', 'PropertyCount', 'nTSecurityDescriptor') 
            } | ForEach-Object {
                $value = $_.Value
                if ($value -is [System.Collections.ICollection]) {
                    $export[$_.Name] = ($value | ForEach-Object { $_.ToString() }) -join "; "
                }
                elseif ($null -ne $value) {
                    $export[$_.Name] = $value.ToString()
                }
                else {
                    $export[$_.Name] = ""
                }
            }
            
            $results += [PSCustomObject]$export
            $success++
            Write-Host "OK" -ForegroundColor Green
        }
        catch {
            $failed++
            Write-Host "FAILED" -ForegroundColor Red
            Write-Host "        Error: $($_.Exception.Message)" -ForegroundColor DarkRed
            
            # Add failed entry with basic info
            $results += [PSCustomObject]@{
                SamAccountName = $userName
                _Status = "FAILED"
                _Error = $_.Exception.Message
            }
        }
    }
    
    # Export to CSV
    Write-Host ""
    Write-Host "============================================="  -ForegroundColor Green
    Write-Host "              BATCH COMPLETE                 " -ForegroundColor Green
    Write-Host "============================================="  -ForegroundColor Green
    Write-Host ""
    Write-Host "[+] Successful: " -NoNewline -ForegroundColor Green
    Write-Host $success -ForegroundColor White
    Write-Host "[-] Failed:     " -NoNewline -ForegroundColor Red
    Write-Host $failed -ForegroundColor White
    Write-Host ""
    
    if ($results.Count -gt 0) {
        try {
            $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            Write-Host "[+] Data exported to: " -NoNewline -ForegroundColor Green
            Write-Host $OutputPath -ForegroundColor Cyan
            Write-Host ""
            
            # Ask to open folder
            $openFolder = Read-Host "Open output folder? (Y/N)"
            if ($openFolder -match '^[Yy]') {
                $folder = Split-Path $OutputPath -Parent
                Start-Process explorer.exe -ArgumentList $folder
            }
        }
        catch {
            Write-Host "[X] Error exporting CSV: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    return $results
}

# Function to display user selection menu
function Show-UserMenu {
    param(
        [string]$CurrentUser
    )
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host "         SELECT USER TO QUERY                " -ForegroundColor Magenta
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  [1] Use local logged-in user: " -NoNewline -ForegroundColor Cyan
    Write-Host $CurrentUser -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [2] Enter user manually" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [3] Batch process from file (TXT/CSV)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [0] Exit" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host ""
    
    do {
        $choice = Read-Host "Choose an option (0-3)"
        
        switch ($choice) {
            "1" {
                return $CurrentUser
            }
            "2" {
                Write-Host ""
                $manualUser = Read-Host "Enter the user login/username"
                if ([string]::IsNullOrWhiteSpace($manualUser)) {
                    Write-Host "[!] User cannot be empty. Try again." -ForegroundColor Red
                    $choice = $null
                } else {
                    return $manualUser.Trim()
                }
            }
            "3" {
                return "__BATCH_MODE__"
            }
            "0" {
                Write-Host ""
                Write-Host "Exiting..." -ForegroundColor DarkGray
                exit 0
            }
            default {
                Write-Host "[!] Invalid option. Enter 0, 1, 2 or 3." -ForegroundColor Red
                $choice = $null
            }
        }
    } while ($null -eq $choice)
}

# Function to display output format menu
function Show-OutputMenu {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host "          DATA DISPLAY FORMAT                " -ForegroundColor Magenta
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  [1] Summary (main fields)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [2] ALL fields (all attributes)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [3] Export to CSV" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [4] Export profile photo" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [0] Back" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host ""
    
    do {
        $choice = Read-Host "Choose an option (0-4)"
        
        switch ($choice) {
            "1" { return "summary" }
            "2" { return "all" }
            "3" { return "csv" }
            "4" { return "photo" }
            "0" { return "back" }
            default {
                Write-Host "[!] Invalid option. Enter 0, 1, 2, 3 or 4." -ForegroundColor Red
                $choice = $null
            }
        }
    } while ($null -eq $choice)
}

# Function to display ALL fields (always expanded)
function Show-AllFields {
    param($User)
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "       ALL USER ATTRIBUTES (" -NoNewline -ForegroundColor Green
    Write-Host "$($User.PropertyCount)" -NoNewline -ForegroundColor Yellow
    Write-Host " fields)        " -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host ""
    
    $User.PSObject.Properties | Where-Object { $_.Name -notin @('PropertyNames', 'AddedProperties', 'RemovedProperties', 'ModifiedProperties', 'PropertyCount') } | Sort-Object Name | ForEach-Object {
        $name = $_.Name
        $value = $_.Value
        
        # Format special values
        if ($null -eq $value -or $value -eq '') {
            Write-Host ("{0,-45}" -f $name) -NoNewline -ForegroundColor Yellow
            Write-Host ": " -NoNewline
            Write-Host "(empty)" -ForegroundColor DarkGray
        }
        elseif ($value -is [System.Collections.ICollection]) {
            if ($value.Count -eq 0) {
                Write-Host ("{0,-45}" -f $name) -NoNewline -ForegroundColor Yellow
                Write-Host ": " -NoNewline
                Write-Host "(empty)" -ForegroundColor DarkGray
            }
            else {
                # Always expand arrays/collections
                Write-Host ("{0,-45}" -f $name) -NoNewline -ForegroundColor Yellow
                Write-Host ": " -NoNewline -ForegroundColor White
                Write-Host "[$($value.Count) items]" -ForegroundColor Magenta
                
                $index = 0
                foreach ($item in $value) {
                    $index++
                    $itemStr = $item.ToString()
                    
                    # For AD DNs, extract friendly name
                    if ($itemStr -match '^CN=([^,]+)') {
                        $friendlyName = $Matches[1]
                        Write-Host ("{0,45}  " -f "") -NoNewline
                        Write-Host ("[{0:D2}] " -f $index) -NoNewline -ForegroundColor DarkGray
                        Write-Host $friendlyName -NoNewline -ForegroundColor Cyan
                        Write-Host " ($itemStr)" -ForegroundColor DarkGray
                    }
                    elseif ($item -is [byte]) {
                        # For byte arrays, display in hex
                        if ($index -eq 1) {
                            $hexValues = ($value | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                            if ($hexValues.Length -gt 100) {
                                $hexValues = $hexValues.Substring(0, 100) + "..."
                            }
                            Write-Host ("{0,45}  " -f "") -NoNewline
                            Write-Host "[HEX] " -NoNewline -ForegroundColor DarkGray
                            Write-Host $hexValues -ForegroundColor Gray
                        }
                        break
                    }
                    else {
                        Write-Host ("{0,45}  " -f "") -NoNewline
                        Write-Host ("[{0:D2}] " -f $index) -NoNewline -ForegroundColor DarkGray
                        Write-Host $itemStr -ForegroundColor White
                    }
                }
            }
        }
        elseif ($value -is [DateTime]) {
            Write-Host ("{0,-45}" -f $name) -NoNewline -ForegroundColor Yellow
            Write-Host ": " -NoNewline
            Write-Host $value.ToString("dd/MM/yyyy HH:mm:ss") -ForegroundColor Cyan
        }
        elseif ($value -is [bool]) {
            Write-Host ("{0,-45}" -f $name) -NoNewline -ForegroundColor Yellow
            Write-Host ": " -NoNewline
            $color = if ($value) { "Green" } else { "Red" }
            Write-Host $value.ToString() -ForegroundColor $color
        }
        else {
            Write-Host ("{0,-45}" -f $name) -NoNewline -ForegroundColor Yellow
            Write-Host ": " -NoNewline
            Write-Host $value.ToString() -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Green
}

# Function to export to CSV
function Export-ToCsv {
    param($User, [string]$Path)
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $Path = Join-Path $env:TEMP "ADUser_$($User.SamAccountName)_$timestamp.csv"
    }
    
    try {
        $export = @{}
        $User.PSObject.Properties | Where-Object { $_.Name -notin @('PropertyNames', 'AddedProperties', 'RemovedProperties', 'ModifiedProperties', 'PropertyCount', 'nTSecurityDescriptor') } | ForEach-Object {
            $value = $_.Value
            if ($value -is [System.Collections.ICollection]) {
                $export[$_.Name] = ($value | ForEach-Object { $_.ToString() }) -join "; "
            }
            elseif ($null -ne $value) {
                $export[$_.Name] = $value.ToString()
            }
            else {
                $export[$_.Name] = ""
            }
        }
        
        [PSCustomObject]$export | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        
        Write-Host ""
        Write-Host "[+] Data exported to: " -NoNewline -ForegroundColor Green
        Write-Host $Path -ForegroundColor Cyan
        Write-Host ""
        
        return $Path
    }
    catch {
        Write-Host "[X] Error exporting: $_" -ForegroundColor Red
        return $null
    }
}

# Function to export profile photo
function Export-UserPhoto {
    param(
        $User,
        [string]$Path,
        [string]$Domain
    )
    
    # Fetch photo (requires specific query as it doesn't come with -Properties *)
    try {
        $userWithPhoto = Get-ADUser -Identity $User.SamAccountName -Server $Domain -Properties thumbnailPhoto, jpegPhoto -ErrorAction Stop
    }
    catch {
        Write-Host "[!] Error fetching photo: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $null
    }
    
    $photoData = $null
    $photoSource = $null
    
    # Check thumbnailPhoto first (most common)
    if ($userWithPhoto.thumbnailPhoto -and $userWithPhoto.thumbnailPhoto.Length -gt 0) {
        $photoData = $userWithPhoto.thumbnailPhoto
        $photoSource = "thumbnailPhoto"
    }
    # Fallback to jpegPhoto
    elseif ($userWithPhoto.jpegPhoto -and $userWithPhoto.jpegPhoto.Length -gt 0) {
        $photoData = $userWithPhoto.jpegPhoto
        $photoSource = "jpegPhoto"
    }
    
    if (-not $photoData) {
        return @{
            HasPhoto = $false
            Message = "User does not have a photo registered in AD"
        }
    }
    
    # Define output path
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $Path = Join-Path $env:TEMP "ADPhoto_$($User.SamAccountName)_$timestamp.jpg"
    }
    
    try {
        [System.IO.File]::WriteAllBytes($Path, $photoData)
        
        return @{
            HasPhoto = $true
            Path = $Path
            Size = $photoData.Length
            Source = $photoSource
        }
    }
    catch {
        return @{
            HasPhoto = $true
            Error = $_.Exception.Message
        }
    }
}

# Get current system user
$CurrentLoggedUser = $env:USERNAME

# Configuration
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$DllPath = Join-Path $ScriptPath "Microsoft.ActiveDirectory.Management.dll"
$ModulePath = Join-Path $ScriptPath "ActiveDirectory\ActiveDirectory.psd1"

# Function to request domain from user
function Request-DomainFromUser {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host "       DOMAIN NOT DETECTED AUTOMATICALLY      " -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Enter the Active Directory domain." -ForegroundColor White
    Write-Host "You can enter multiple domains separated by comma." -ForegroundColor DarkGray
    Write-Host "Example: " -NoNewline -ForegroundColor DarkGray
    Write-Host "company.local, company.corp, ad.company.com" -ForegroundColor Cyan
    Write-Host ""
    
    do {
        $inputDomain = Read-Host "Domain(s)"
        if ([string]::IsNullOrWhiteSpace($inputDomain)) {
            Write-Host "[!] Domain cannot be empty. Try again." -ForegroundColor Red
        }
    } while ([string]::IsNullOrWhiteSpace($inputDomain))
    
    # Return array of domains (cleaned)
    return ($inputDomain -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# Function to test domain connection
function Test-DomainConnection {
    param([string]$DomainName)
    
    try {
        $null = Get-ADDomainController -DomainName $DomainName -Discover -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Function to detect domain
function Get-CurrentDomain {
    try {
        # Method 1: Environment variable
        if ($env:USERDNSDOMAIN) {
            Write-Verbose "Domain detected via USERDNSDOMAIN: $env:USERDNSDOMAIN"
            return $env:USERDNSDOMAIN
        }

        # Method 2: WMI/CIM
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($computerSystem.Domain -and $computerSystem.Domain -ne "WORKGROUP") {
            Write-Verbose "Domain detected via WMI: $($computerSystem.Domain)"
            return $computerSystem.Domain
        }

        # Method 3: .NET
        $domainInfo = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        if ($domainInfo.Name) {
            Write-Verbose "Domain detected via .NET: $($domainInfo.Name)"
            return $domainInfo.Name
        }
    }
    catch {
        Write-Verbose "Could not detect domain automatically: $_"
    }
    
    return $null
}

# Banner
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   AD User Info - Query without Admin/RSAT   " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Check for batch mode from parameter
$BatchMode = $false
if ($BatchFile) {
    $BatchMode = $true
}

# Determine which user to query
if ($BatchMode) {
    $TargetUser = "__BATCH_MODE__"
    Write-Host "[*] Batch mode (from parameter)" -ForegroundColor DarkGray
}
elseif ($NoMenu -and $SamAccountName) {
    # Direct mode without menu
    $TargetUser = $SamAccountName
    Write-Host "[*] Direct mode (no menu)" -ForegroundColor DarkGray
}
elseif ($SamAccountName) {
    # Has user as parameter, but displays menu to confirm
    Write-Host "[*] User provided via parameter: " -NoNewline -ForegroundColor Yellow
    Write-Host $SamAccountName -ForegroundColor White
    $TargetUser = Show-UserMenu -CurrentUser $CurrentLoggedUser
}
else {
    # Display menu to choose
    $TargetUser = Show-UserMenu -CurrentUser $CurrentLoggedUser
}

# Handle batch mode selection from menu
if ($TargetUser -eq "__BATCH_MODE__") {
    $BatchMode = $true
    
    # Get input file
    if (-not $BatchFile) {
        Write-Host ""
        Write-Host "[*] Select the input file with user list..." -ForegroundColor Yellow
        $BatchFile = Show-OpenFileDialog -Title "Select User List File" -Filter "Text Files (*.txt)|*.txt|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"
        
        if (-not $BatchFile) {
            Write-Host "[X] No file selected. Exiting." -ForegroundColor Red
            exit 1
        }
    }
    
    Write-Host "[*] Input file: " -NoNewline -ForegroundColor Green
    Write-Host $BatchFile -ForegroundColor Cyan
    
    # Get output file
    if (-not $BatchOutput) {
        Write-Host ""
        Write-Host "[*] Select the output CSV file..." -ForegroundColor Yellow
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $BatchOutput = Show-SaveFileDialog -Title "Save Results As" -DefaultFileName "AD_Users_Export_$timestamp.csv"
        
        if (-not $BatchOutput) {
            Write-Host "[X] No output file selected. Exiting." -ForegroundColor Red
            exit 1
        }
    }
    
    Write-Host "[*] Output file: " -NoNewline -ForegroundColor Green
    Write-Host $BatchOutput -ForegroundColor Cyan
}

if (-not $BatchMode) {
    Write-Host ""
    Write-Host "[*] Selected user: " -NoNewline -ForegroundColor Green
    Write-Host $TargetUser -ForegroundColor White
}

# Detect or use specified domain
$DomainList = @()

if ($Domain) {
    # Domain(s) provided via parameter - can be comma-separated list
    $DomainList = $Domain -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    Write-Host "[*] Specified domain(s): " -NoNewline -ForegroundColor Yellow
    Write-Host ($DomainList -join ', ') -ForegroundColor White
}
else {
    Write-Host "[*] Detecting domain automatically..." -ForegroundColor Yellow
    $DetectedDomain = Get-CurrentDomain
    
    if ($DetectedDomain) {
        $DomainList = @($DetectedDomain)
        Write-Host "[+] Domain detected: " -NoNewline -ForegroundColor Green
        Write-Host $DetectedDomain -ForegroundColor White
    }
    else {
        # Request domain from user
        $DomainList = Request-DomainFromUser
        Write-Host "[*] Provided domain(s): " -NoNewline -ForegroundColor Yellow
        Write-Host ($DomainList -join ', ') -ForegroundColor White
    }
}

# Use the first domain in the list as primary
$TargetDomain = $DomainList[0]

# Load AD module
Write-Host ""
Write-Host "[*] Loading ADModule..." -ForegroundColor Yellow

try {
    # Check if DLL exists
    if (-not (Test-Path $DllPath)) {
        throw "DLL not found at: $DllPath"
    }

    # Import DLL
    Import-Module $DllPath -ErrorAction Stop
    Write-Host "[+] DLL loaded successfully" -ForegroundColor Green

    # Try to import full module (for more cmdlets)
    if (Test-Path $ModulePath) {
        try {
            Import-Module $ModulePath -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            Write-Host "[+] Full module loaded" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] .psd1 module not loaded (basic cmdlets available)" -ForegroundColor DarkYellow
        }
    }
}
catch {
    Write-Host "[X] Error loading module: $_" -ForegroundColor Red
    exit 1
}

# Handle batch mode processing
if ($BatchMode) {
    # Read users from file
    $usersToProcess = Read-UsersFromFile -FilePath $BatchFile
    
    if ($usersToProcess.Count -eq 0) {
        Write-Host "[X] No users found in the file or file is empty." -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
    Write-Host "[*] Found " -NoNewline -ForegroundColor Green
    Write-Host $usersToProcess.Count -NoNewline -ForegroundColor Yellow
    Write-Host " user(s) in file" -ForegroundColor Green
    
    # Process batch
    $batchResults = Process-BatchUsers -Users $usersToProcess -OutputPath $BatchOutput -TargetDomain $TargetDomain
    
    Write-Host ""
    exit 0
}

# Single user query mode
Write-Host ""
Write-Host "[*] Querying user: " -NoNewline -ForegroundColor Yellow
Write-Host $TargetUser -ForegroundColor White

# Try each domain in the list until successful
$User = $null
$SuccessDomain = $null

foreach ($tryDomain in $DomainList) {
    Write-Host "[*] Trying domain: " -NoNewline -ForegroundColor Yellow
    Write-Host $tryDomain -ForegroundColor White
    
    try {
        $User = Get-ADUser -Identity $TargetUser -Server $tryDomain -Properties * -ErrorAction Stop
        $SuccessDomain = $tryDomain
        Write-Host "[+] Successfully connected to domain: " -NoNewline -ForegroundColor Green
        Write-Host $tryDomain -ForegroundColor White
        break
    }
    catch {
        Write-Host "[!] Failed on domain $tryDomain : $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

if (-not $User) {
    Write-Host ""
    Write-Host "[X] Could not query user in any of the provided domains." -ForegroundColor Red
    Write-Host "[!] Please verify that:" -ForegroundColor Yellow
    Write-Host "    - You are connected to the corporate network/VPN" -ForegroundColor Yellow
    Write-Host "    - The domain name is correct" -ForegroundColor Yellow
    Write-Host "    - The user '$TargetUser' exists in the domain" -ForegroundColor Yellow
    exit 1
}

$TargetDomain = $SuccessDomain
Write-Host ""

try {

    # Determine output format
    if ($AllFields) {
        $outputFormat = "all"
    }
    elseif ($ExportCsv) {
        $outputFormat = "csv"
    }
    elseif (-not $NoMenu) {
        $outputFormat = Show-OutputMenu
        if ($outputFormat -eq "back") {
            Write-Host "Operation cancelled." -ForegroundColor DarkGray
            exit 0
        }
    }
    else {
        $outputFormat = "summary"
    }

    # Display according to chosen format
    switch ($outputFormat) {
        "all" {
            Show-AllFields -User $User
        }
        "csv" {
            $csvPath = if ($ExportCsv) { $ExportCsv } else { $null }
            Export-ToCsv -User $User -Path $csvPath
        }
        "photo" {
            $photoPath = if ($ExportPhoto) { $ExportPhoto } else { $null }
            $photoResult = Export-UserPhoto -User $User -Path $photoPath -Domain $TargetDomain
            
            if ($photoResult.HasPhoto) {
                if ($photoResult.Path) {
                    Write-Host ""
                    Write-Host "[+] Photo exported successfully!" -ForegroundColor Green
                    Write-Host "    Source: " -NoNewline -ForegroundColor White
                    Write-Host $photoResult.Source -ForegroundColor Cyan
                    Write-Host "    Size: " -NoNewline -ForegroundColor White
                    Write-Host "$([math]::Round($photoResult.Size / 1024, 2)) KB" -ForegroundColor Cyan
                    Write-Host "    File: " -NoNewline -ForegroundColor White
                    Write-Host $photoResult.Path -ForegroundColor Yellow
                    Write-Host ""
                    
                    # Ask if user wants to open
                    $openPhoto = Read-Host "Do you want to open the photo? (Y/N)"
                    if ($openPhoto -match '^[Yy]') {
                        Start-Process $photoResult.Path
                    }
                }
                else {
                    Write-Host "[X] Error saving photo: $($photoResult.Error)" -ForegroundColor Red
                }
            }
            else {
                Write-Host ""
                Write-Host "[!] $($photoResult.Message)" -ForegroundColor DarkYellow
                Write-Host ""
            }
        }
        default {
            # Display summary (default format)
            Write-Host "=============================================" -ForegroundColor Green
            Write-Host "            USER INFORMATION                 " -ForegroundColor Green
            Write-Host "=============================================" -ForegroundColor Green
            Write-Host ""

            # Basic data
            Write-Host "--- Identification ---" -ForegroundColor Cyan
            Write-Host ("Full Name:         {0}" -f $User.DisplayName)
            Write-Host ("First Name:        {0}" -f $User.GivenName)
            Write-Host ("Last Name:         {0}" -f $User.Surname)
            Write-Host ("Login (SAM):       {0}" -f $User.SamAccountName)
            Write-Host ("UPN:               {0}" -f $User.UserPrincipalName)
            Write-Host ("Email:             {0}" -f $User.EmailAddress)
            Write-Host ("Employee ID:       {0}" -f $User.EmployeeID)
            Write-Host ("Employee Number:   {0}" -f $User.EmployeeNumber)
            Write-Host ""

            # Organization
            Write-Host "--- Organization ---" -ForegroundColor Cyan
            Write-Host ("Title/Position:    {0}" -f $User.Title)
            Write-Host ("Department:        {0}" -f $User.Department)
            Write-Host ("Company:           {0}" -f $User.Company)
            Write-Host ("Manager:           {0}" -f $User.Manager)
            Write-Host ("Office:            {0}" -f $User.Office)
            Write-Host ("Description:       {0}" -f $User.Description)
            Write-Host ""

            # Contact
            Write-Host "--- Contact ---" -ForegroundColor Cyan
            Write-Host ("Telephone:         {0}" -f $User.TelephoneNumber)
            Write-Host ("Mobile:            {0}" -f $User.MobilePhone)
            Write-Host ("Fax:               {0}" -f $User.Fax)
            Write-Host ("Home Phone:        {0}" -f $User.HomePhone)
            Write-Host ""

            # Address
            Write-Host "--- Address ---" -ForegroundColor Cyan
            Write-Host ("Street:            {0}" -f $User.StreetAddress)
            Write-Host ("City:              {0}" -f $User.City)
            Write-Host ("State:             {0}" -f $User.State)
            Write-Host ("Postal Code:       {0}" -f $User.PostalCode)
            Write-Host ("Country:           {0}" -f $User.Country)
            Write-Host ""

            # Account status
            Write-Host "--- Account Status ---" -ForegroundColor Cyan
            Write-Host ("Account Enabled:   {0}" -f $User.Enabled)
            Write-Host ("Account Locked:    {0}" -f $User.LockedOut)
            Write-Host ("Password Expired:  {0}" -f $User.PasswordExpired)
            Write-Host ("Password Never Expires:{0}" -f $User.PasswordNeverExpires)
            Write-Host ("Last Logon:        {0}" -f $User.LastLogonDate)
            Write-Host ("Password Changed:  {0}" -f $User.PasswordLastSet)
            Write-Host ("Account Created:   {0}" -f $User.Created)
            Write-Host ("Last Modified:     {0}" -f $User.Modified)
            Write-Host ""

            # AD Location
            Write-Host "--- AD Location ---" -ForegroundColor Cyan
            Write-Host ("Distinguished Name:{0}" -f $User.DistinguishedName)
            Write-Host ("Canonical Name:    {0}" -f $User.CanonicalName)
            Write-Host ("SID:               {0}" -f $User.SID)
            Write-Host ("GUID:              {0}" -f $User.ObjectGUID)
            Write-Host ""

            # Check profile photo
            Write-Host "--- Profile Photo ---" -ForegroundColor Cyan
            $photoCheck = Export-UserPhoto -User $User -Path $null -Domain $TargetDomain
            if ($photoCheck.HasPhoto -and $photoCheck.Path) {
                Write-Host "Photo available:   " -NoNewline
                Write-Host "Yes" -ForegroundColor Green
                Write-Host ("Size:              {0} KB" -f [math]::Round($photoCheck.Size / 1024, 2))
                Write-Host ("Source:            {0}" -f $photoCheck.Source)
                Write-Host ("Saved to:          {0}" -f $photoCheck.Path)
            }
            else {
                Write-Host "Photo available:   " -NoNewline
                Write-Host "No" -ForegroundColor DarkGray
            }
            Write-Host ""

            # Groups (if available)
            if ($User.MemberOf) {
                Write-Host "--- Groups (MemberOf) ---" -ForegroundColor Cyan
                $User.MemberOf | ForEach-Object {
                    $groupName = ($_ -split ',')[0] -replace 'CN=', ''
                    Write-Host ("  - {0}" -f $groupName)
                }
                Write-Host ""
            }

            Write-Host "=============================================" -ForegroundColor Green
            Write-Host ""
        }
    }

    # Return object for later use
    $User
}
catch {
    Write-Host "[X] Error processing user data: " -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
