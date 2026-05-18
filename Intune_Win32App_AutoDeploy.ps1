<#
.SYNOPSIS
Bulk Win32 App Upload to Intune
#>

param(
    [switch]$ValidateConfig
)


# =====================================================
# Global Variables
# =====================================================

$basePath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$appsPath = Join-Path $basePath "Apps"
$intuneUtilPath = Join-Path $basePath "IntuneWinAppUtil.exe"

$logFolder = Join-Path $basePath "Logs"

$global:AppsProcessed = 0
$global:AppsSucceeded = 0
$global:AppsFailed = 0

if (!(Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder | Out-Null
}

$logPath = Join-Path $logFolder "DeployLog_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"

Start-Transcript -Path $logPath -Append

# =====================================================
# Tenant Details
# =====================================================

# Values from your Entra ID app registration
$tenantId     = "1c32ec8f-cfb8-4ac1-afcf-06627b2d2b69"
$clientId     = "fae17952-33eb-4ea4-872c-2c5950801cba"
$clientSecret = $env:INTUNE_CLIENT_SECRET



# =====================================================
# Logging Functions
# =====================================================

function Write-Log {

    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    switch ($Level) {

        "INFO" {
            $color = "White"
        }

        "WARN" {
            $color = "Yellow"
        }

        "ERROR" {
            $color = "Red"
        }

        "SUCCESS" {
            $color = "Green"
        }
    }

    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}



# =====================================================
# Install & Import Required Modules
# =====================================================

$requiredModules = @(
    "MSAL.PS",
    "IntuneWin32App"
)

foreach ($module in $requiredModules) {

    Write-Log "Checking module: $module"

    if (-not (Get-Module -ListAvailable -Name $module)) {

        Write-Log "Module not found. Installing $module..." "ERROR"

        try {

            Install-Module `
                -Name $module `
                -Scope CurrentUser `
                -Force `
                -AllowClobber `
                -ErrorAction Stop

            Write-Log "$module installed successfully." "SUCCESS"
        }
        catch {

            Write-Log "Failed to install module: $module" "ERROR"
            Write-Log $_.Exception.Message

            Stop-Transcript
            exit
        }
    }
    else {

        Write-log "module already installed." "SUCCESS"
    }

    try {

        Import-Module $module -Force -ErrorAction Stop

        Write-Log "$module imported successfully." "SUCCESS"
    }
    catch {

        Write-log "Failed to import module: $module" "ERROR"
        Write-log $_.Exception.Message

        Stop-Transcript
        exit
    }
}

# =====================================================
# Authentication
# =====================================================

function Get-GraphToken {

    Write-log "Authenticating to Graph..."

    $secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force

    $token = Get-MsalToken `
        -ClientId $clientId `
        -TenantId $tenantId `
        -ClientSecret $secureSecret `
        -Scopes "https://graph.microsoft.com/.default"

    return $token.AccessToken
}

# =====================================================
# Read Config
# =====================================================

function Get-AppConfig {

    param(
        [string]$ConfigPath
    )

    try {
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-log "Invalid JSON: $ConfigPath" "ERROR"
        return $null
    }
}


# =====================================================
# Validate Config
# =====================================================

function Test-AppConfig {

    param(
        [object]$Config,
        [string]$ConfigPath
    )

    $requiredProperties = @(
        "DisplayName",
        "Description",
        "Publisher",
        "AppVersion",
        "InstallerName",
        "InstallCmd",
        "UninstallCmd"
    )

    $validationFailed = $false

    foreach ($property in $requiredProperties) {

        if (-not $Config.PSObject.Properties[$property]) {

            Write-log "Missing required property '$property' in: $ConfigPath" "ERROR"
            
           $validationFailed = $true

            continue
        }

        $value = $Config.$property

        if ([string]::IsNullOrWhiteSpace($value)) {

           Write-log "Property '$property' is empty in: $ConfigPath" "ERROR"
           
           $validationFailed = $true
        }
    }

    # Validate DetectionRules
    if ($Config.DetectionRules) {

        foreach ($rule in $Config.DetectionRules) {

            switch ($rule.Type) {

                "MSI" {

                    if (-not $rule.ProductCode) {

                        Write-log "MSI detection rule missing ProductCode in: $ConfigPath" "ERROR"

                        $validationFailed = $true
                    }
                }

                "Registry" {

                    if (-not $rule.KeyPath) {

                        Write-log "Registry detection rule missing KeyPath in: $ConfigPath" "ERROR"

                        $validationFailed = $true
                    }
                }

                "File" {

                    if (-not $rule.Path) {

                        Write-log "File detection rule missing Path in: $ConfigPath" "ERROR"

                        $validationFailed = $true
                    }
                }
            }
        }
    }


    # Validate folder name matches DisplayName
    $folderName = Split-Path $ConfigPath -Parent | Split-Path -Leaf

    if ($folderName -ne $Config.DisplayName) {

        Write-Log @"
        Folder name does not match DisplayName.

        Folder Name : $folderName
        DisplayName : $($Config.DisplayName)
        Config File : $ConfigPath
"@ "ERROR"

        $validationFailed = $true
    }



    return (-not $validationFailed)
}




# =====================================================
# Create IntuneWin Package
# =====================================================

function New-IntuneWinPackage {

    param(
        [string]$AppFolder,
        [object]$AppConfig
    )

    if (!(Test-Path $intuneUtilPath)) {

        Write-Log "IntuneWinAppUtil.exe not found." "ERROR"

        return $null
    }


    $installerPath = Join-Path $AppFolder $AppConfig.InstallerName

    if (!(Test-Path $installerPath)) {

        Write-log "Installer missing: $installerPath" "ERROR"
        return $null
    }

    Write-log "Packaging $($AppConfig.DisplayName)..."

        # Remove old package
        Get-ChildItem $AppFolder -Filter *.intunewin -ErrorAction SilentlyContinue |
            Remove-Item -Force

        $arguments = @(
            "-c `"$AppFolder`""
            "-s `"$($AppConfig.InstallerName)`""
            "-o `"$AppFolder`""
            "-q"
        )


        Start-Process `
            -FilePath $intuneUtilPath `
            -ArgumentList $arguments `
            -Wait `
            -WindowStyle Hidden


        $package = Get-ChildItem `
            -Path $AppFolder `
            -Filter *.intunewin `
            -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($package) {

            Write-log "Package created:" "SUCCESS"
            Write-log $package.FullName

            return $package.FullName
        }

        Write-log "Package creation failed."  "ERROR"

        return $null
}

# =====================================================
# Build Detection Rules
# =====================================================

function Get-DetectionRules {

    param(
        [object]$AppConfig
    )

    $rules = @()

    foreach ($rule in $AppConfig.DetectionRules) {

        if ($rule.Enabled -ne $true) {
            continue
        }

        switch ($rule.Type) {

            "MSI" {

                $rules += New-IntuneWin32AppDetectionRuleMSI `
                    -ProductCode $rule.productCode `
                    -ProductVersionOperator $rule.productVersionOperator `
                    -ProductVersion $rule.productVersion
            }

            "Registry" {

                $rules += New-IntuneWin32AppDetectionRuleRegistry `
                    -Existence `
                    -KeyPath $rule.KeyPath `
                    -ValueName $rule.ValueName `
                    -DetectionType version `
                    -Operator greaterThanOrEqual `
                    -VersionValue $rule.VersionValue `
                    -Check32BitOn64System $false
                            }

            "File" {

                $fileName = Split-Path $rule.Path -Leaf
                $folder = Split-Path $rule.Path

                $rules += New-IntuneWin32AppDetectionRuleFile `
                    -Existence `
                    -Path $rule.Path `
                    -FileOrFolder $rule.FileOrFolderName `
                    -DetectionType version `
                    -Operator greaterThanOrEqual `
                    -VersionValue $rule.VersionValue `
                    -Check32BitOn64System $false
                            }
        }
    }

    return $rules
}

# =====================================================
# Ensure Entra Group Exists
# =====================================================

function Ensure-EntraGroup {

    param(
        [string]$Token,
        [object]$AppConfig
    )

    if ($AppConfig.CreateGroup -ne "Yes") {

        Write-log "Group creation disabled. Skipping..."
        return $null
    }

    $groupName = $AppConfig.EntraIDGroupName.Trim()

    Write-log "Checking Entra group: $groupName"

    $headers = @{
        Authorization  = "Bearer $Token"
        "Content-Type" = "application/json"
    }

    try {

        # Get groups directly
        $uri = "https://graph.microsoft.com/v1.0/groups?`$select=id,displayName&`$top=999"

        $response = Invoke-RestMethod `
            -Uri $uri `
            -Headers $headers `
            -Method GET `
            -ErrorAction Stop

        # Exact match locally
        $existingGroup = $response.value | Where-Object {
            $_.displayName.Trim().ToLower() -eq $groupName.ToLower()
        } | Select-Object -First 1

        if ($existingGroup) {

            Write-log "Group already exists." "SUCCESS"
            Write-log "Existing Group ID: $($existingGroup.id)"

            return $existingGroup.id
        }

        Write-log "Group not found. Creating new group..." "WARN"

        # Generate safe nickname
        $mailNickname = (
            $groupName `
            -replace '[^a-zA-Z0-9]', ''
        )

        if ([string]::IsNullOrWhiteSpace($mailNickname)) {
            $mailNickname = "IntuneAppGroup"
        }

        if ($mailNickname.Length -gt 40) {
            $mailNickname = $mailNickname.Substring(0,40)
        }

        # nickname must be unique
        $mailNickname = "$mailNickname$(Get-Random -Maximum 99999)"

        $body = @{
            displayName     = $groupName
            description     = "Created by Win32 App AutoDeploy"
            mailEnabled     = $false
            mailNickname    = $mailNickname
            securityEnabled = $true
        } | ConvertTo-Json -Depth 5

        $newGroup = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/groups" `
            -Headers $headers `
            -Method POST `
            -Body $body `
            -ErrorAction Stop

        Write-log "Group created successfully." "SUCCESS"
        Write-log "New Group ID: $($newGroup.id)"
        
        return $newGroup.id
    }
    catch {

        Write-Log "Failed during group validation/creation." "SUCCESS"

        if ($_.Exception.Response) {

            $resp = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($resp)

            Write-log $reader.ReadToEnd()
        }
        else {

            Write-log $_.Exception.Message
        }

        return $null
    }
}

function Upload-Win32Application {

    param(
        [string]$PackagePath,
        [object]$AppConfig
    )

    Write-log "Uploading app: $($AppConfig.DisplayName)"

    # Authenticate to Intune Graph
    Connect-MSIntuneGraph `
        -TenantID $tenantId `
        -ClientID $clientId `
        -ClientSecret $clientSecret

    $detectionRules = Get-DetectionRules -AppConfig $AppConfig

    Write-log "PackagePath:"
    Write-log $PackagePath

    if (!(Test-Path $PackagePath)) {

        Write-log "Package path does not exist." "ERROR"
        return
    }


       $app = @(Add-IntuneWin32App `
            -FilePath $PackagePath `
            -DisplayName $AppConfig.DisplayName `
            -Description $AppConfig.Description `
            -Publisher $AppConfig.Publisher `
            -AppVersion $AppConfig.AppVersion `
            -InstallCommandLine $AppConfig.InstallCmd `
            -UninstallCommandLine $AppConfig.UninstallCmd `
            -InstallExperience "system" `
            -RestartBehavior "suppress" `
            -DetectionRule $detectionRules
        )

        $appObject = $app | Where-Object {
            $_.id
        } | Select-Object -Last 1

        if (!$appObject) {

            Write-log "Failed to retrieve uploaded app object." "ERROR"
            return $null
        }

        $appId = $appObject.id

        Write-log "Uploaded App ID: $appId" "SUCCESS"

        return $appId

}

# =====================================================
# Assign App
# =====================================================

function Assign-Win32Application {

    param(
        [string]$AppId,
        [string]$GroupId,
        [object]$AppConfig
    )

    if ($AppConfig.AssignApp -ne "Yes") {

        Write-log "Assignment disabled. Skipping..."
        return
    }

    if (!$GroupId) {

        Write-log "Group ID missing. Cannot assign app." "ERROR"
        return
    }

    # Normalize App ID
    $AppId = "$AppId".Trim()

    if ($AppId -match '[0-9a-fA-F-]{36}') {

        $AppId = $matches[0]
    }

    Write-log "Normalized App ID: $AppId"

    Write-log "Assigning app..."

    # Authenticate
    Connect-MSIntuneGraph `
        -TenantID $tenantId `
        -ClientID $clientId `
        -ClientSecret $clientSecret

    try {

        # Check existing assignments
        $existingAssignments = Get-IntuneWin32AppAssignment -ID $AppId

        $alreadyAssigned = $existingAssignments | Where-Object {
            $_.target.groupId -eq $GroupId
        }

        if ($alreadyAssigned) {

            Write-log "App already assigned to group. Skipping..." "WARN"
            return
        }

        # Create assignment
        Add-IntuneWin32AppAssignmentGroup `
            -Include `
            -ID $AppId `
            -GroupID $GroupId `
            -Intent "available" `
            -ErrorAction Stop

        Write-log "App assigned successfully." "SUCCESS"
    }
    catch {

        Write-log "Failed to assign app." "ERROR"

        Write-log $_.Exception.Message
    }
}


# =====================================================
# Process Apps
# =====================================================

function Process-Apps {

    $token = Get-GraphToken

    if (!$token) {
        Write-log "Authentication failed." "ERROR"
        return
    }

    $folders = Get-ChildItem $appsPath -Directory

    foreach ($folder in $folders) {

        Write-log "====================================="
        Write-log "Processing: $($folder.Name)"
        Write-log "====================================="

        $configPath = Join-Path $folder.FullName "config.json"

        if (!(Test-Path $configPath)) {

            Write-log "config.json missing." "WARN"
            continue
        }

        $config = Get-AppConfig -ConfigPath $configPath

        Write-Log "Validating Config file."

        if (!(Test-AppConfig -Config $config -ConfigPath $configPath)) {

            Write-log "Config validation failed. Skipping app." "ERROR"

            continue
        }

        if ($ValidateConfig) {

            Write-Log "Validation successful for config file: $($config.DisplayName)" "SUCCESS"

            continue
        }


        $packagePath = New-IntuneWinPackage `
            -AppFolder $folder.FullName `
            -AppConfig $config

        if (!$packagePath) {
            continue
        }

        $groupId = Ensure-EntraGroup `
            -Token $token `
            -AppConfig $config

        $appId = Upload-Win32Application `
            -Token $token `
            -PackagePath $packagePath `
            -AppConfig $config

        if ($appId -and $groupId) {

          Assign-Win32Application `
            -AppId $appId `
            -GroupId $groupId `
            -AppConfig $config
                }

        Write-log ""

          $global:AppsProcessed+=1
    }

  

}

# =====================================================
# Main
# =====================================================

Write-log "Starting deployment..."

Process-Apps

Write-Log "====================================="
Write-Log "Deployment Summary"
Write-Log "Processed : $global:AppsProcessed"
Write-Log "Succeeded : $global:AppsSucceeded" "SUCCESS"
Write-Log "Failed    : $global:AppsFailed"
Write-Log "====================================="

Stop-Transcript