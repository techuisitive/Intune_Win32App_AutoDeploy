**Intune Win32 App Bulk Upload**

Bulk upload and manage Microsoft Intune Win32 applications using PowerShell and Microsoft Graph API. This solution helps administrators automate Win32 app creation, assignment, detection rules, requirement rules, icons, and .intunewin package uploads in bulk.

**Features**

Bulk upload Win32 applications to Microsoft Intune
Upload .intunewin packages automatically
Configure install and uninstall commands
Support for detection and requirement rules
Assign applications during upload
Configure install context (System/User)
Add application metadata including publisher, description, version, and categories
Upload application icons
Reduce manual effort and deployment time
Easily scalable for MSP and enterprise environments

**Prerequisites**

Microsoft Intune Administrator or Global Administrator access
Microsoft Graph PowerShell SDK installed
PowerShell 7.x recommended
.intunewin packages prepared using Microsoft Win32 Content Prep Tool
Required Graph API permissions consented
Windows device for running the script
Required PowerShell Modules

**Install the required modules before running the script:**

Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module IntuneWin32App -Scope CurrentUser

**Folder Structure**

Intune-Win32-Bulk-Upload
│
├── Apps
│   ├── 7zip
│   │   ├── 7zip.intunewin
│   │   ├── icon.png
│   │   └── app.json
│   │
│   └── NotepadPlusPlus
│       ├── npp.intunewin
│       ├── icon.png
│       └── app.json
│
├── Upload-Win32Apps.ps1
└── README.md

**Sample JSON Configuration**

{
  "DisplayName": "Notepad++",
  "Description": "Notepad++ Win32 App",
  "Publisher": "Notepad++",
  "InstallCommandLine": "msiexec /i npp.msi /qn",
  "UninstallCommandLine": "msiexec /x {GUID} /qn",
  "InstallExperience": "system",
  "RestartBehavior": "suppress",
  "DetectionRule": {
    "Type": "MSI",
    "ProductCode": "{PRODUCT-CODE}"
  },
}

**How It Works**

Reads application configuration from JSON files
Validates required metadata and package files
Connects to Microsoft Graph API
Uploads .intunewin packages to Intune
Creates Win32 applications automatically
Configures detection and requirement rules
Uploads application icons
Assigns applications to Azure AD groups
Logs upload progress and errors
Supported Configuration Options

**Configuration	Supported**

Win32 App Upload	Yes
Install Commands	Yes
Uninstall Commands	Yes
Detection Rules	Yes
Requirement Rules	Yes
Assignments	Yes
Icons	Yes
System/User Context	Yes
Restart Behavior	Yes
Dependencies	Planned
Supersedence	Planned

**Example Usage**

.\Upload-Win32Apps.ps1 -AppFolder ".\Apps"
Output Example
[INFO] Connecting to Microsoft Graph...
[INFO] Uploading Notepad++...
[SUCCESS] Win32 app created successfully
[INFO] Assigning application...
[SUCCESS] Assignment completed

**Benefits**
Faster Intune application onboarding
Standardized Win32 app deployments
Reduced manual configuration errors
Ideal for large-scale deployments
Helpful for MSP environments managing multiple tenants
Simplifies application lifecycle management

**Use Cases**
Enterprise application onboarding
MSP multi-tenant Intune management
Application migration to Intune
Standardized Win32 deployment automation
Rapid software rollout projects

**Roadmap**
Dependency support
Supersedence support
Azure Blob package storage integration
GUI version
Logging dashboard
CSV-driven app imports
Automatic icon extraction
Contributing

Contributions, improvements, and feature suggestions are welcome.

**Author**
Scripts maintained by Equebal Ahmad
Visit Techuisitive.com for full tutorials. 

**Complete Tutorial **

https://techuisitive.com/bulk-win32-app-deployment-to-intune-using-powershell-and-microsoft-graph-api/

