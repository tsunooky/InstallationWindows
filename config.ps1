#Requires -Version 5.1
<#
.SYNOPSIS
    Optimisation Windows 11 - post-installation script.

.DESCRIPTION
    Applies the privacy, performance and debloat settings described in the
    InstallationWindows guide, installs the base applications, manages the
    reversible modules (Xbox, printing, WSL/virtualization, OneDrive) and runs
    a read-only health check of the hardware configuration.

    Usage: copy this file to the Desktop, right-click > "Exécuter avec PowerShell".
    The script elevates itself. It is safe to run again at any time.
#>

[CmdletBinding()]
param()

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$ScriptVersion = '2.0.0'
$MinBuild      = 26100
$DataDir       = Join-Path $env:ProgramData 'OptimisationWindows'
$StatePath     = Join-Path $DataDir 'state.json'
$LogPath       = Join-Path $DataDir ('config-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))

$SchemeBalanced   = '381b4222-f694-41f0-9685-ff5bb260df2e'
$OverlayBestPerf  = 'ded574b5-45a0-4f42-8737-46345c09c238'
$NullPersistentHandler = '{098f2470-bae0-11cd-b579-08002b30bfeb}'

# Services that run by default on a clean install and are useless here.
# Rule: only services that are actually running on a fresh Windows 26H2.
$ServicesToDisable = @(
    'DiagTrack'   # Connected User Experiences and Telemetry
)

# Xbox apps with background processes. Xbox Identity Provider and TCUI are kept:
# they have no process and Steam games using Xbox Live need them.
$XboxPackages = @(
    'Microsoft.GamingApp',
    'Microsoft.GamingServices',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxGameOverlay',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.Edge.GameAssist'
)

# Microsoft Store IDs used to reinstall the Xbox apps.
$XboxStoreIds = [ordered]@{
    'Xbox'           = '9MV0B5HZVK9Z'
    'Xbox Game Bar'  = '9NZKPSTSNW4P'
}

# File types indexed by name and properties only (content not indexed).
$PropertiesOnlyExtensions = @(
    '.txt', '.log', '.md', '.csv', '.json', '.xml', '.ini', '.cfg', '.yml', '.yaml', '.toml',
    '.ps1', '.psm1', '.bat', '.cmd', '.sh', '.py', '.js', '.mjs', '.ts', '.tsx', '.jsx',
    '.java', '.c', '.cpp', '.h', '.hpp', '.cs', '.go', '.rs', '.php', '.rb', '.lua', '.sql',
    '.html', '.htm', '.css', '.scss', '.vue',
    '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.pdf', '.rtf', '.odt', '.ods', '.odp'
)

# Telemetry scheduled tasks (missing tasks are ignored).
$TelemetryTasks = @(
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
)

# ---------------------------------------------------------------------------
# Elevation, PowerShell edition and Windows version checks
# ---------------------------------------------------------------------------

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-Exit([string]$Message) {
    if ($Message) { Write-Host ''; Write-Host "  $Message" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '  Appuie sur Entrée pour fermer.' -ForegroundColor DarkGray
    [void](Read-Host)
    exit
}

if (-not $PSCommandPath) {
    Wait-Exit 'Lance ce script depuis le fichier config.ps1 (clic droit > Exécuter avec PowerShell).'
}

# Always run in an elevated Windows PowerShell 5.1 (Appx and DISM cmdlets need it).
if (-not (Test-Admin) -or $PSVersionTable.PSEdition -eq 'Core') {
    $argList = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    try {
        $verb = if (Test-Admin) { 'Open' } else { 'RunAs' }
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $argList -Verb $verb | Out-Null
    } catch {
        Wait-Exit 'Les droits administrateur sont nécessaires. Relance le script et accepte la demande.'
    }
    exit
}

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$Host.UI.RawUI.WindowTitle = 'Optimisation Windows'

if ([Environment]::OSVersion.Version.Build -lt $MinBuild) {
    Wait-Exit ('Windows 11 24H2 ou plus récent est requis (build {0} détectée, {1} minimum).' -f [Environment]::OSVersion.Version.Build, $MinBuild)
}

if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -Path $DataDir -ItemType Directory -Force | Out-Null }

# ---------------------------------------------------------------------------
# Logging and low-level helpers
# ---------------------------------------------------------------------------

function Write-OwLog([string]$Message, [string]$Level = 'INFO') {
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    try { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 } catch { }
}

function Set-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')]
        [string]$Type = 'DWord'
    )
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Get-RegValue([string]$Path, [string]$Name) {
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    return $item.$Name
}

function Invoke-Native {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @(), [int[]]$OkCodes = @(0))
    $ErrorActionPreference = 'Continue'
    $output = & $File @Arguments 2>&1 | Out-String
    if ($OkCodes -notcontains $LASTEXITCODE) {
        throw ('{0} {1} a échoué (code {2}) : {3}' -f $File, ($Arguments -join ' '), $LASTEXITCODE, $output.Trim())
    }
    return $output
}

function Set-ServiceStartup {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Disabled', 'Manual', 'Automatic')][string]$Startup,
        [switch]$Stop,
        [switch]$Start
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $false }
    if ($Stop -and $svc.Status -ne 'Stopped') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    try {
        Set-Service -Name $Name -StartupType $Startup -ErrorAction Stop
    } catch {
        # Some services refuse Set-Service: fall back to the registry Start value.
        $startValue = @{ 'Automatic' = 2; 'Manual' = 3; 'Disabled' = 4 }[$Startup]
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name 'Start' -Value $startValue
    }
    if ($Start) { Start-Service -Name $Name -ErrorAction SilentlyContinue }
    return $true
}

function Disable-TaskByPath([string]$FullPath) {
    $taskName = Split-Path -Path $FullPath -Leaf
    $taskPath = $FullPath.Substring(0, $FullPath.Length - $taskName.Length)
    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task -and $task.State -ne 'Disabled') { $task | Disable-ScheduledTask | Out-Null }
}

function Remove-Shortcut([string[]]$Names) {
    $desktops = @([Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('Desktop'))
    foreach ($desktop in $desktops) {
        foreach ($name in $Names) {
            $path = Join-Path $desktop $name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ---------------------------------------------------------------------------
# Console UI
# ---------------------------------------------------------------------------

function Write-Title {
    Clear-Host
    Write-Host ''
    Write-Host '  Optimisation Windows' -ForegroundColor White -NoNewline
    Write-Host ("  v$ScriptVersion") -ForegroundColor DarkGray
    Write-Host ''
}

function Write-Section([string]$Title) {
    Write-Host ''
    Write-Host "  $Title" -ForegroundColor White
}

function Wait-Key([string]$Message = 'Appuie sur une touche pour continuer...') {
    Write-Host ''
    Write-Host "  $Message" -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

# Generic arrow-key menu. Items: hashtables with Label, optional Status,
# StatusColor, Hint and SpaceBefore. Returns the selected index.
function Read-Menu {
    param([string]$Header, [object[]]$Items, [int]$Default = 0)
    $index = $Default
    while ($true) {
        Write-Title
        if ($Header) { Write-Host "  $Header"; Write-Host '' }
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            if ($item.SpaceBefore) { Write-Host '' }
            $selected = ($i -eq $index)
            $prefix = if ($selected) { '  > ' } else { '    ' }
            $color = if ($selected) { 'Cyan' } else { 'Gray' }
            Write-Host ($prefix + ([string]$item.Label).PadRight(30)) -ForegroundColor $color -NoNewline
            if ($item.Status) {
                $statusColor = if ($item.StatusColor) { $item.StatusColor } else { 'DarkGray' }
                Write-Host $item.Status -ForegroundColor $statusColor
            } else {
                Write-Host ''
            }
        }
        Write-Host ''
        if ($Items[$index].Hint) { Write-Host ('  ' + $Items[$index].Hint) -ForegroundColor Yellow }
        Write-Host '  Flèches haut/bas : naviguer   Entrée : valider' -ForegroundColor DarkGray
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $index = ($index - 1 + $Items.Count) % $Items.Count }
            'DownArrow' { $index = ($index + 1) % $Items.Count }
            'Enter'     { return $index }
        }
    }
}

function Read-YesNo([string]$Question, [bool]$Default = $true) {
    $items = @(@{ Label = 'Oui' }, @{ Label = 'Non' })
    $defaultIndex = if ($Default) { 0 } else { 1 }
    return ((Read-Menu -Header $Question -Items $items -Default $defaultIndex) -eq 0)
}

# Checkbox list. Items: hashtables with Label, Hint, Value (bool). Returns the items.
function Read-Checkboxes {
    param([string]$Header, [object[]]$Items)
    $index = 0
    while ($true) {
        Write-Title
        if ($Header) { Write-Host "  $Header"; Write-Host '' }
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            $selected = ($i -eq $index)
            $prefix = if ($selected) { '  > ' } else { '    ' }
            $box = if ($item.Value) { '[x] ' } else { '[ ] ' }
            $color = if ($selected) { 'Cyan' } else { 'Gray' }
            Write-Host $prefix -ForegroundColor $color -NoNewline
            $boxColor = if ($item.Value) { 'Green' } else { 'DarkGray' }
            Write-Host $box -ForegroundColor $boxColor -NoNewline
            Write-Host $item.Label -ForegroundColor $color
        }
        Write-Host ''
        if ($Items[$index].Hint) { Write-Host ('  ' + $Items[$index].Hint) -ForegroundColor Yellow }
        Write-Host '  Flèches : naviguer   Espace : cocher/décocher   Entrée : valider' -ForegroundColor DarkGray
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $index = ($index - 1 + $Items.Count) % $Items.Count }
            'DownArrow' { $index = ($index + 1) % $Items.Count }
            'Spacebar'  { $Items[$index].Value = -not $Items[$index].Value }
            'Enter'     { return $Items }
        }
    }
}

# ---------------------------------------------------------------------------
# Step runner
# ---------------------------------------------------------------------------

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:ManualSteps = New-Object System.Collections.Generic.List[string]

function Skip([string]$Reason) { return "__SKIP__$Reason" }

function Invoke-Step {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][scriptblock]$Action)
    Write-Host ("  ...  $Label") -ForegroundColor DarkGray -NoNewline
    $ErrorActionPreference = 'Stop'
    try {
        $result = @(& $Action)
        $skip = $result | Where-Object { $_ -is [string] -and $_.StartsWith('__SKIP__') } | Select-Object -First 1
        if ($skip) {
            $reason = $skip.Substring(8)
            Write-Host ("`r  --   $Label ($reason)") -ForegroundColor DarkGray
            Write-OwLog "SKIP  $Label : $reason"
        } else {
            Write-Host ("`r  OK   $Label") -ForegroundColor Green
            Write-OwLog "OK    $Label"
        }
    } catch {
        $message = $_.Exception.Message
        Write-Host ("`r  !!   $Label") -ForegroundColor Red
        Write-Host ("       $message") -ForegroundColor DarkRed
        Write-OwLog "FAIL  $Label : $message" 'ERROR'
        $script:Failures.Add($Label)
    }
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

function Get-State {
    if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
    try { return (Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Save-State($State) {
    $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Hardware and system detection
# ---------------------------------------------------------------------------

function Get-GpuVendor([string]$PnpId) {
    if ($PnpId -match 'VEN_10DE') { return 'NVIDIA' }
    if ($PnpId -match 'VEN_1002') { return 'AMD' }
    if ($PnpId -match 'VEN_8086') { return 'Intel' }
    return 'Autre'
}

function Test-DiscreteGpuName([string]$Name) {
    return ($Name -match 'GeForce|RTX|GTX|Quadro|Radeon RX|Radeon Pro|Radeon VII|Arc\(TM\) [AB]\d{3}|Arc [AB]\d{3}')
}

function Get-SystemInfo {
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $cs  = Get-CimInstance -ClassName Win32_ComputerSystem
    $os  = Get-CimInstance -ClassName Win32_OperatingSystem

    $gpus = @(Get-CimInstance -ClassName Win32_VideoController | ForEach-Object {
        [pscustomobject]@{
            Name       = $_.Name
            PnpId      = $_.PNPDeviceID
            Vendor     = Get-GpuVendor $_.PNPDeviceID
            IsDiscrete = Test-DiscreteGpuName $_.Name
            IsBasic    = ($_.Name -match 'Basic Display|de base Microsoft|Microsoft Basic')
        }
    })

    $cpuVendor = switch -Regex ($cpu.Manufacturer) {
        'AMD'   { 'AMD'; break }
        'Intel' { 'Intel'; break }
        default { 'Autre' }
    }

    $ramBytes = (Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    $ramGB = [math]::Round($ramBytes / 1GB)

    $isVm = ($cs.Manufacturer -match 'QEMU|VMware|innotek|Xen|Parallels') -or
            ($cs.Model -match 'Virtual|KVM|VMware|VirtualBox|Q35|i440FX')

    $hasLinux = $false
    try {
        $hasLinux = [bool](Get-Partition -ErrorAction Stop | Where-Object { $_.GptType -eq '{0FC63DAF-8483-4772-8E79-3D69D8477DE4}' })
    } catch {
        Write-OwLog ("Lecture des partitions impossible : {0}" -f $_.Exception.Message) 'WARN'
    }

    [pscustomobject]@{
        CpuName        = $cpu.Name.Trim()
        CpuVendor      = $cpuVendor
        IsDualCcdX3D   = ($cpu.Name -match '7900X3D|7950X3D|9900X3D|9950X3D')
        Gpus           = $gpus
        HasDiscreteArc = [bool]($gpus | Where-Object { $_.Vendor -eq 'Intel' -and $_.IsDiscrete })
        HasNvidia      = [bool]($gpus | Where-Object { $_.Vendor -eq 'NVIDIA' })
        IsLaptop       = [bool](Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
        IsVM           = $isVm
        RamGB          = $ramGB
        HasLinux       = $hasLinux
        Edition        = $os.Caption
        Build          = [Environment]::OSVersion.Version.Build
    }
}

function Get-GpuSummary($Info) {
    $names = @($Info.Gpus | Where-Object { -not $_.IsBasic } | ForEach-Object { $_.Name })
    if ($names.Count -eq 0) { $names = @($Info.Gpus | ForEach-Object { $_.Name }) }
    return ($names -join ' + ')
}

# ---------------------------------------------------------------------------
# Module state detection
# ---------------------------------------------------------------------------

function Get-XboxEnabled { return [bool](Get-AppxPackage -Name 'Microsoft.GamingApp' -ErrorAction SilentlyContinue) -or [bool](Get-AppxPackage -Name 'Microsoft.XboxGamingOverlay' -ErrorAction SilentlyContinue) }

function Get-PrintingEnabled {
    $svc = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
    return ($svc -and $svc.StartType -ne 'Disabled')
}

function Get-VirtualizationEnabled {
    foreach ($feature in 'VirtualMachinePlatform', 'Microsoft-Windows-Subsystem-Linux', 'Microsoft-Hyper-V-All') {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
        if ($f -and $f.State -eq 'Enabled') { return $true }
    }
    return $false
}

function Get-OneDriveInstalled {
    return (Test-Path -LiteralPath "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or
           (Test-Path -LiteralPath "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")
}

# ---------------------------------------------------------------------------
# winget
# ---------------------------------------------------------------------------

function Initialize-Winget {
    if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue) { return $true }
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
    } catch {
        Write-OwLog ("Enregistrement de winget impossible : {0}" -f $_.Exception.Message) 'WARN'
    }
    return [bool](Get-Command -Name 'winget' -ErrorAction SilentlyContinue)
}

function Test-WingetInstalled([string]$Id, [string]$Source = 'winget') {
    $ErrorActionPreference = 'Continue'
    & winget list --id $Id --exact --source $Source --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-WingetPackage([string]$Id, [string]$Source = 'winget') {
    if (Test-WingetInstalled -Id $Id -Source $Source) { return (Skip 'déjà installé') }
    $arguments = @('install', '--id', $Id, '--exact', '--source', $Source, '--silent',
                   '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    Invoke-Native -File 'winget' -Arguments $arguments | Out-Null
}

function Uninstall-WingetPackage([string]$Id) {
    if (-not (Test-WingetInstalled -Id $Id)) { return (Skip 'non installé') }
    Invoke-Native -File 'winget' -Arguments @('uninstall', '--id', $Id, '--exact', '--silent', '--accept-source-agreements', '--disable-interactivity') | Out-Null
}

# ---------------------------------------------------------------------------
# Optimizations (no rollback)
# ---------------------------------------------------------------------------

function Invoke-PrivacySteps($Info) {
    Write-Section 'Confidentialité et télémétrie'

    Invoke-Step 'Services de télémétrie et services inutiles' {
        foreach ($name in $ServicesToDisable) { [void](Set-ServiceStartup -Name $name -Startup Disabled -Stop) }
    }

    Invoke-Step 'Tâches planifiées de télémétrie' {
        foreach ($task in $TelemetryTasks) { Disable-TaskByPath $task }
    }

    Invoke-Step "Rapport d'erreurs Windows" {
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    }

    Invoke-Step 'Télémétrie PowerShell' {
        [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
    }

    Invoke-Step 'Publicité ciblée et expériences personnalisées' {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0
    }

    Invoke-Step 'Personnalisation de la saisie et de l''écriture' {
        Set-RegValue 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
        Set-RegValue 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
        Set-RegValue 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
    }

    Invoke-Step 'Localisation' {
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
    }

    Invoke-Step 'Demandes de commentaires' {
        Set-RegValue 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
    }

    Invoke-Step 'Recherche web et cloud dans le menu Démarrer' {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsMSACloudSearchEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsAADCloudSearchEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDeviceSearchHistoryEnabled' 0
    }

    Invoke-Step "Defender : pas d'envoi automatique d'échantillons" {
        if (-not (Get-Command -Name 'Set-MpPreference' -ErrorAction SilentlyContinue)) { return (Skip 'Defender absent') }
        Set-MpPreference -SubmitSamplesConsent 2
    }

    if ($Info.HasNvidia) {
        Invoke-Step 'Télémétrie NVIDIA' {
            Set-RegValue 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0
            Get-ScheduledTask -TaskName 'NvTm*' -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
        }
    }
}

function Invoke-AiSteps {
    Write-Section 'IA et Copilot'

    Invoke-Step 'Copilot' {
        Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    }

    Invoke-Step 'Recall, Click to Do et agent des Paramètres' {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
        Set-RegValue $key 'DisableAIDataAnalysis' 1
        Set-RegValue $key 'AllowRecallEnablement' 0
        Set-RegValue $key 'DisableClickToDo' 1
        Set-RegValue $key 'DisableSettingsAgent' 1
        Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    }

    Invoke-Step 'IA dans le Bloc-notes et Paint' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1
        $paint = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'
        Set-RegValue $paint 'DisableCocreator' 1
        Set-RegValue $paint 'DisableGenerativeFill' 1
        Set-RegValue $paint 'DisableImageCreator' 1
    }
}

function Invoke-SystemSteps($Info, $Choices) {
    Write-Section 'Système et services'

    Invoke-Step 'SysMain' {
        if ($Info.RamGB -lt 32) { return (Skip ("conservé, {0} Go de RAM" -f $Info.RamGB)) }
        [void](Set-ServiceStartup -Name 'SysMain' -Startup Disabled -Stop)
    }

    Invoke-Step 'Hibernation' {
        Invoke-Native -File 'powercfg.exe' -Arguments @('/hibernate', 'off') | Out-Null
    }

    Invoke-Step 'Applications en arrière-plan' {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
        $allowed = @('Microsoft.SecHealthUI_8wekyb3d8bbwe')
        if ($Choices.Xbox) { $allowed += 'Microsoft.GamingApp_8wekyb3d8bbwe', 'Microsoft.XboxGamingOverlay_8wekyb3d8bbwe' }
        Set-RegValue $key 'LetAppsRunInBackground' 2
        Set-RegValue $key 'LetAppsRunInBackground_ForceAllowTheseApps' ([string[]]$allowed) 'MultiString'
    }

    Invoke-Step 'Partage pair-à-pair des mises à jour' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    }

    Invoke-Step 'Assistance à distance' {
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
    }

    Invoke-Step 'Reprise d''activités et appareils connectés' {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        Set-RegValue $key 'EnableCdp' 0
        Set-RegValue $key 'EnableActivityFeed' 0
        Set-RegValue $key 'PublishUserActivities' 0
        Set-RegValue $key 'UploadUserActivities' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration' 'IsResumeAllowed' 0
    }

    Invoke-Step 'Heures d''activité Windows Update (8 h - 2 h)' {
        $key = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        Set-RegValue $key 'SmartActiveHoursState' 0
        Set-RegValue $key 'ActiveHoursStart' 8
        Set-RegValue $key 'ActiveHoursEnd' 2
    }

    Invoke-Step 'Pas de reconnexion automatique après une mise à jour' {
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableAutomaticRestartSignOn' 1
    }

    Invoke-Step 'Horloge compatible Linux (dual boot)' {
        if (-not $Info.HasLinux) { return (Skip 'aucune partition Linux') }
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' 'RealTimeIsUniversal' 1
    }
}

function Invoke-PowerSteps($Info) {
    Write-Section 'Alimentation et latence'

    if ($Info.IsLaptop) {
        Invoke-Step 'Réglages d''alimentation' { return (Skip 'portable, gestion laissée au constructeur') }
        return
    }

    Invoke-Step 'Plan Équilibré + mode « Meilleures performances »' {
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setactive', $SchemeBalanced) | Out-Null
        try {
            Invoke-Native -File 'powercfg.exe' -Arguments @('/overlaysetactive', $OverlayBestPerf) | Out-Null
        } catch {
            $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
            Set-RegValue $key 'ActiveOverlayAcPowerScheme' $OverlayBestPerf 'String'
            Set-RegValue $key 'ActiveOverlayDcPowerScheme' $OverlayBestPerf 'String'
        }
    }

    Invoke-Step 'Gestion d''alimentation PCI Express' {
        if ($Info.HasDiscreteArc) { return (Skip 'GPU Intel Arc, conservée') }
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setacvalueindex', $SchemeBalanced, 'SUB_PCIEXPRESS', 'ASPM', '0') | Out-Null
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setdcvalueindex', $SchemeBalanced, 'SUB_PCIEXPRESS', 'ASPM', '0') | Out-Null
    }

    Invoke-Step 'Mise en veille sélective USB' {
        $sub = '2a737441-1930-4402-8d77-b2bebba308a3'; $setting = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setacvalueindex', $SchemeBalanced, $sub, $setting, '0') | Out-Null
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setdcvalueindex', $SchemeBalanced, $sub, $setting, '0') | Out-Null
    }

    Invoke-Step 'Économie d''énergie Wi-Fi' {
        $sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'; $setting = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setacvalueindex', $SchemeBalanced, $sub, $setting, '0') | Out-Null
    }

    Invoke-Step 'Activation du plan d''alimentation modifié' {
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setactive', $SchemeBalanced) | Out-Null
    }

    Invoke-Step 'Économie d''énergie des cartes réseau' {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
        if ($adapters.Count -eq 0) { return (Skip 'aucune carte détectée') }
        $keywords = @('*EEE', 'EEE', 'AdvancedEEE', 'EnableGreenEthernet', 'GigaLite', 'PowerSavingMode', 'ULPMode')
        foreach ($adapter in $adapters) {
            if ($adapter.NdisPhysicalMedium -eq 14) {
                foreach ($keyword in $keywords) {
                    $prop = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -ErrorAction SilentlyContinue
                    if ($prop -and "$($prop.RegistryValue)" -ne '0') {
                        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -RegistryValue '0' -NoRestart -ErrorAction SilentlyContinue
                    }
                }
            }
            try {
                Set-NetAdapterPowerManagement -Name $adapter.Name -AllowComputerToTurnOffDevice Disabled -NoRestart -ErrorAction Stop
            } catch {
                Write-OwLog ("Carte {0} : gestion d'alimentation non modifiable ({1})" -f $adapter.Name, $_.Exception.Message) 'WARN'
            }
        }
    }
}

function Invoke-GamingSteps {
    Write-Section 'Jeu et affichage'

    Invoke-Step 'Optimisations pour les jeux en fenêtre et VRR' {
        $key = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
        $name = 'DirectXUserGlobalSettings'
        $settings = [ordered]@{}
        $current = Get-RegValue $key $name
        if ($current) {
            foreach ($pair in ($current -split ';')) {
                if ($pair -match '^(.+?)=(.*)$') { $settings[$Matches[1]] = $Matches[2] }
            }
        }
        $settings['SwapEffectUpgradeEnable'] = '1'
        $settings['VRROptimizeEnable'] = '1'
        $value = (($settings.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }) -join ';') + ';'
        Set-RegValue $key $name $value 'String'
    }

    Invoke-Step 'Enregistrement en arrière-plan (Game DVR)' {
        Set-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 0
    }
}

function Invoke-SearchSteps {
    Write-Section 'Recherche'

    Invoke-Step 'Indexation des documents : noms et propriétés seulement' {
        $failed = 0
        foreach ($ext in $PropertiesOnlyExtensions) {
            try {
                $key = "HKLM:\SOFTWARE\Classes\$ext\PersistentHandler"
                $current = Get-RegValue $key '(default)'
                if ($current -eq $NullPersistentHandler) { continue }
                if ($current) { Set-RegValue $key 'OriginalPersistentHandler' $current 'String' }
                Set-RegValue $key '(default)' $NullPersistentHandler 'String'
            } catch { $failed++ }
        }
        if ($failed -gt 0) { Write-OwLog "Indexation : $failed extension(s) non modifiée(s)" 'WARN' }
    }
}

function Invoke-EdgeSteps {
    Write-Section 'Microsoft Edge'

    Invoke-Step 'Edge en arrière-plan et démarrage anticipé' {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        Set-RegValue $key 'StartupBoostEnabled' 0
        Set-RegValue $key 'BackgroundModeEnabled' 0
        Set-RegValue $key 'HideFirstRunExperience' 1
        Set-RegValue $key 'HubsSidebarEnabled' 0
        Set-RegValue $key 'ShowRecommendationsEnabled' 0
        Set-RegValue $key 'SpotlightExperiencesAndRecommendationsEnabled' 0
        Set-RegValue $key 'DefaultBrowserSettingEnabled' 0
    }

    Invoke-Step 'Mises à jour Edge : vérification quotidienne seulement' {
        Get-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachineUA*' -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
        [void](Set-ServiceStartup -Name 'edgeupdate' -Startup Manual)
        [void](Set-ServiceStartup -Name 'edgeupdatem' -Startup Manual)
    }

    Invoke-Step 'Raccourci Edge sur le Bureau' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0
        Remove-Shortcut @('Microsoft Edge.lnk')
    }
}

function Invoke-InterfaceSteps {
    Write-Section 'Interface, clavier et audio'

    Invoke-Step 'Icône de Sécurité Windows dans la barre des tâches' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray' 'HideSystray' 1
    }

    Invoke-Step 'Raccourci Alt+Maj de changement de clavier' {
        $key = 'HKCU:\Keyboard Layout\Toggle'
        Set-RegValue $key 'Hotkey' '3' 'String'
        Set-RegValue $key 'Language Hotkey' '3' 'String'
        Set-RegValue $key 'Layout Hotkey' '3' 'String'
    }

    Invoke-Step 'Raccourcis d''accessibilité (touches rémanentes, filtres, bascules)' {
        Set-RegValue 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
        Set-RegValue 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'
        Set-RegValue 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String'
    }

    Invoke-Step 'Correction automatique et surlignage orthographique' {
        Set-RegValue 'HKCU:\Software\Microsoft\TabletTip\1.7' 'EnableAutocorrection' 0
        Set-RegValue 'HKCU:\Software\Microsoft\TabletTip\1.7' 'EnableSpellchecking' 0
    }

    Invoke-Step 'Menu Démarrer : plus d''épingles' {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_Layout' 1
    }

    Invoke-Step 'Atténuation du son pendant les appels' {
        Set-RegValue 'HKCU:\Software\Microsoft\Multimedia\Audio' 'UserDuckingPreference' 3
    }

    Invoke-Step 'Améliorations audio' {
        $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
        $endpoints = @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue |
            Where-Object { (Get-RegValue $_.PSPath 'DeviceState') -eq 1 })
        if ($endpoints.Count -eq 0) { return (Skip 'aucune sortie audio active') }
        $failed = 0
        foreach ($endpoint in $endpoints) {
            try {
                Set-RegValue (Join-Path $endpoint.PSPath 'FxProperties') '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5' 1
            } catch { $failed++ }
        }
        if ($failed -gt 0) {
            $script:ManualSteps.Add('Paramètres > Système > Son > (ta sortie audio) > Améliorations audio : Désactivé')
            throw "accès refusé sur $failed sortie(s) : à faire à la main (voir la fin du script)"
        }
    }
}

function Invoke-NotificationSteps {
    Write-Section 'Notifications'

    Invoke-Step 'Notifications coupées (sauf Sécurité Windows et Windows Update)' {
        $base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
        if (-not (Test-Path -LiteralPath $base)) { New-Item -Path $base -Force | Out-Null }
        $keep = 'Security|SecHealth|Defender|WindowsUpdate|UpdateOrchestrator|MoNotification|Windows\.Update'
        foreach ($notifier in Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue) {
            $value = if ($notifier.PSChildName -match $keep) { 1 } else { 0 }
            Set-RegValue $notifier.PSPath 'Enabled' $value
            Write-OwLog ("Notifications {0} : {1}" -f $notifier.PSChildName, $value)
        }
        Set-RegValue $base 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
    }
}

function Invoke-CleanupSteps {
    Write-Section 'Nettoyage'

    Invoke-Step 'Fichiers temporaires' {
        foreach ($dir in @($env:TEMP, "$env:SystemRoot\Temp")) {
            Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Invoke-Step 'Anciennes versions des composants Windows (quelques minutes)' {
        Invoke-Native -File 'dism.exe' -Arguments @('/Online', '/Cleanup-Image', '/StartComponentCleanup', '/Quiet') | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Applications
# ---------------------------------------------------------------------------

function Set-FirefoxPolicies {
    $firefoxDir = Join-Path $env:ProgramFiles 'Mozilla Firefox'
    if (-not (Test-Path -LiteralPath $firefoxDir)) { return (Skip 'Firefox absent') }
    $distribution = Join-Path $firefoxDir 'distribution'
    if (-not (Test-Path -LiteralPath $distribution)) { New-Item -Path $distribution -ItemType Directory -Force | Out-Null }
    $policies = [ordered]@{
        policies = [ordered]@{
            DisableTelemetry        = $true
            DisableFirefoxStudies   = $true
            DisablePocket           = $true
            DisableProfileImport    = $true
            DontCheckDefaultBrowser = $true
            DisableDefaultBrowserAgent = $true
            FirefoxHome = [ordered]@{
                SponsoredTopSites = $false
                SponsoredPocket   = $false
                Pocket            = $false
            }
            ExtensionSettings = [ordered]@{
                'uBlock0@raymondhill.net' = [ordered]@{
                    installation_mode = 'normal_installed'
                    install_url       = 'https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi'
                }
            }
        }
    }
    $json = $policies | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $distribution 'policies.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    [Environment]::SetEnvironmentVariable('MOZ_CRASHREPORTER_DISABLE', '1', 'Machine')
}

function Disable-StartupEntry([string]$Name) {
    # Same flag Task Manager writes when an entry is disabled (03 + timestamp).
    $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTimeUtc()))
    Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' $Name $bytes 'Binary'
}

function Invoke-AppSteps($Choices) {
    Write-Section 'Applications'

    if (-not (Initialize-Winget)) {
        Invoke-Step 'winget' { throw 'winget est introuvable : mets à jour « Programme d''installation d''application » depuis le Microsoft Store, puis relance.' }
        return
    }

    Invoke-Step 'Firefox' { Install-WingetPackage 'Mozilla.Firefox.fr' }
    Invoke-Step 'Firefox : uBlock Origin et confidentialité' { Set-FirefoxPolicies }
    Invoke-Step 'VLC' {
        $result = Install-WingetPackage 'VideoLAN.VLC'
        Remove-Shortcut @('VLC media player.lnk')
        $result
    }
    Invoke-Step '7-Zip' { Install-WingetPackage '7zip.7zip' }

    if ($Choices.Steam) {
        Invoke-Step 'Steam' { Install-WingetPackage 'Valve.Steam' }
        Invoke-Step 'Steam : pas de lancement au démarrage' { Disable-StartupEntry 'Steam' }
    }
    if ($Choices.Discord) {
        Invoke-Step 'Discord' { Install-WingetPackage 'Discord.Discord' }
        Invoke-Step 'Discord : pas de lancement au démarrage' { Disable-StartupEntry 'Discord' }
    }

    Invoke-Step 'Raccourcis Bureau inutiles' { Remove-Shortcut @('Microsoft Edge.lnk', 'VLC media player.lnk') }
}

# ---------------------------------------------------------------------------
# Reversible modules
# ---------------------------------------------------------------------------

function Disable-Xbox([bool]$KeepGameBar = $false) {
    Invoke-Step 'Suppression des applis Xbox' {
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
        foreach ($name in $XboxPackages) {
            if ($KeepGameBar -and $name -eq 'Microsoft.XboxGamingOverlay') { continue }
            Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue |
                Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            $provisioned | Where-Object { $_.DisplayName -eq $name } |
                Remove-AppxProvisionedPackage -Online -AllUsers -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

function Enable-Xbox {
    if (-not (Initialize-Winget)) { Invoke-Step 'winget' { throw 'winget est introuvable.' }; return }
    foreach ($entry in $XboxStoreIds.GetEnumerator()) {
        $id = $entry.Value
        Invoke-Step ("Installation : {0}" -f $entry.Key) { Install-WingetPackage -Id $id -Source 'msstore' }
    }
}

function Disable-Printing {
    Invoke-Step 'Spouleur d''impression' { [void](Set-ServiceStartup -Name 'Spooler' -Startup Disabled -Stop) }
    Invoke-Step 'Imprimantes virtuelles PDF et XPS' {
        foreach ($feature in 'Printing-PrintToPDFServices-Features', 'Printing-XPSServices-Features') {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($f -and $f.State -eq 'Enabled') { Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null }
        }
    }
}

function Enable-Printing {
    Invoke-Step 'Spouleur d''impression' { [void](Set-ServiceStartup -Name 'Spooler' -Startup Automatic -Start) }
    Invoke-Step 'Imprimantes virtuelles PDF et XPS' {
        foreach ($feature in 'Printing-PrintToPDFServices-Features', 'Printing-XPSServices-Features') {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($f -and $f.State -ne 'Enabled') { Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null }
        }
    }
}

function Disable-Virtualization {
    Invoke-Step 'WSL, plateformes de virtualisation, Hyper-V et Sandbox' {
        foreach ($feature in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform', 'HypervisorPlatform', 'Microsoft-Hyper-V-All', 'Containers-DisposableClientVM') {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($f -and $f.State -eq 'Enabled') { Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null }
        }
    }
    Invoke-Step 'Hyperviseur au démarrage' {
        Invoke-Native -File 'bcdedit.exe' -Arguments @('/set', 'hypervisorlaunchtype', 'off') | Out-Null
    }
}

function Enable-Virtualization {
    Invoke-Step 'WSL et plateformes de virtualisation' {
        foreach ($feature in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform', 'HypervisorPlatform') {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($f -and $f.State -ne 'Enabled') { Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null }
        }
    }
    Invoke-Step 'Hyperviseur au démarrage' {
        Invoke-Native -File 'bcdedit.exe' -Arguments @('/set', 'hypervisorlaunchtype', 'auto') | Out-Null
    }
}

function Enable-OneDrive {
    if (-not (Initialize-Winget)) { Invoke-Step 'winget' { throw 'winget est introuvable.' }; return }
    Invoke-Step 'Installation de OneDrive' { Install-WingetPackage 'Microsoft.OneDrive' }
}

function Disable-OneDrive {
    if (-not (Initialize-Winget)) { Invoke-Step 'winget' { throw 'winget est introuvable.' }; return }
    Invoke-Step 'Désinstallation de OneDrive' {
        Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Uninstall-WingetPackage 'Microsoft.OneDrive'
    }
}

function Invoke-ModuleChoices($Info, $Choices) {
    Write-Section 'Modules'
    if (-not $Choices.Xbox) { Disable-Xbox -KeepGameBar ([bool]$Choices.KeepGameBar) }
    if (-not $Choices.Printing) { Disable-Printing }
    if (-not $Choices.Virtualization) { Disable-Virtualization }
}

# ---------------------------------------------------------------------------
# Health check (read only)
# ---------------------------------------------------------------------------

$displayHelperLoaded = $false
function Initialize-DisplayHelper {
    if ($script:displayHelperLoaded) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class OwDisplayInfo
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields; public int dmPositionX; public int dmPositionY;
        public int dmDisplayOrientation; public int dmDisplayFixedOutput;
        public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
        public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent;
        public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2;
        public int dmPanningWidth; public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    public class Result
    {
        public string Adapter; public int Width; public int Height; public int CurrentHz; public int MaxHz;
    }

    public static List<Result> Get()
    {
        var list = new List<Result>();
        for (uint i = 0; ; i++)
        {
            var d = new DISPLAY_DEVICE();
            d.cb = Marshal.SizeOf(d);
            if (!EnumDisplayDevices(null, i, ref d, 0)) break;
            if ((d.StateFlags & 1) == 0) continue; // not attached to the desktop
            var cur = new DEVMODE();
            cur.dmSize = (short)Marshal.SizeOf(cur);
            if (!EnumDisplaySettings(d.DeviceName, -1, ref cur)) continue;
            int max = cur.dmDisplayFrequency;
            var m = new DEVMODE();
            m.dmSize = (short)Marshal.SizeOf(m);
            for (int k = 0; EnumDisplaySettings(d.DeviceName, k, ref m); k++)
            {
                if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight && m.dmDisplayFrequency > max)
                    max = m.dmDisplayFrequency;
            }
            var r = new Result();
            r.Adapter = d.DeviceString; r.Width = cur.dmPelsWidth; r.Height = cur.dmPelsHeight;
            r.CurrentHz = cur.dmDisplayFrequency; r.MaxHz = max;
            list.Add(r);
        }
        return list;
    }
}
'@
    $script:displayHelperLoaded = $true
}

function Write-Check([string]$Level, [string]$Message, [string]$Advice) {
    switch ($Level) {
        'ok'   { Write-Host '  OK   ' -ForegroundColor Green -NoNewline }
        'warn' { Write-Host '  !!   ' -ForegroundColor Red -NoNewline }
        default { Write-Host '  i    ' -ForegroundColor Yellow -NoNewline }
    }
    Write-Host $Message
    if ($Advice) { Write-Host "       -> $Advice" -ForegroundColor DarkGray }
    Write-OwLog ("HEALTH [{0}] {1} {2}" -f $Level, $Message, $Advice)
}

function Get-PciLinkIssue([string]$InstanceId) {
    $id = $InstanceId
    $found = $false
    for ($depth = 0; $depth -lt 4 -and $id; $depth++) {
        $current = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_PciDevice_CurrentLinkWidth' -ErrorAction SilentlyContinue).Data
        $max     = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_PciDevice_MaxLinkWidth' -ErrorAction SilentlyContinue).Data
        if ($current -and $max) {
            $found = $true
            if ($max -ge 8 -and $current -lt $max) { return ('x{0} au lieu de x{1}' -f $current, $max) }
        }
        $id = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue).Data
        if ($id -notlike 'PCI\*') { break }
    }
    if ($found) { return '' }
    return $null
}

function Show-HealthCheck($Info) {
    Write-Section 'Bilan de santé'

    # Secure Boot and TPM
    try {
        if (Confirm-SecureBootUEFI) { Write-Check 'ok' 'Secure Boot actif' }
        else { Write-Check 'warn' 'Secure Boot désactivé' 'Active-le dans le BIOS (requis par Valorant, Battlefield, Call of Duty...)' }
    } catch {
        Write-Check 'warn' 'Secure Boot non disponible' 'Passe le BIOS en mode UEFI (CSM désactivé)'
    }
    $tpm = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
    if ($tpm -and "$($tpm.SpecVersion)" -like '2.0*') { Write-Check 'ok' 'TPM 2.0 présent' }
    else { Write-Check 'warn' 'TPM 2.0 introuvable' 'Active fTPM (AMD) ou PTT (Intel) dans le BIOS' }

    # VBS
    $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg -and $dg.VirtualizationBasedSecurityStatus -eq 2) {
        Write-Check 'warn' 'VBS / intégrité de la mémoire encore actif' 'Sécurité Windows > Sécurité de l''appareil > Isolation du noyau : désactiver, puis redémarrer'
    } else {
        Write-Check 'ok' 'VBS désactivé'
    }

    if ($Info.IsVM) {
        Write-Check 'info' 'Machine virtuelle : vérifications matérielles ignorées'
        return
    }

    # RAM
    $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory)
    $speed = ($modules | Measure-Object -Property ConfiguredClockSpeed -Maximum).Maximum
    $type = ($modules | Select-Object -First 1).SMBIOSMemoryType
    $ramLabel = '{0} Go, {1} barrette(s), {2} MT/s' -f $Info.RamGB, $modules.Count, $speed
    $lowSpeed = (($type -eq 34 -and $speed -le 5600) -or ($type -eq 26 -and $speed -le 2666))
    if ($lowSpeed -and -not $Info.IsLaptop) {
        Write-Check 'warn' "RAM : $ramLabel" 'Vitesse de base : si ton kit est vendu plus rapide, active XMP (Intel) ou EXPO (AMD) dans le BIOS'
    } else {
        Write-Check 'ok' "RAM : $ramLabel"
    }
    if (-not $Info.IsLaptop -and ($modules.Count -eq 1 -or $modules.Count -eq 3)) {
        Write-Check 'warn' 'RAM : pas en double canal' 'Utilise 2 ou 4 barrettes, dans les slots indiqués par le manuel (souvent A2/B2)'
    }

    # Displays
    try {
        Initialize-DisplayHelper
        $displays = [OwDisplayInfo]::Get()
        foreach ($d in $displays) {
            $label = 'Écran {0}x{1} à {2} Hz' -f $d.Width, $d.Height, $d.CurrentHz
            if ($d.MaxHz -gt $d.CurrentHz) {
                Write-Check 'warn' $label ("{0} Hz disponibles : Paramètres > Système > Écran > Affichage avancé" -f $d.MaxHz)
            } else {
                Write-Check 'ok' $label
            }
        }
        $discrete = @($Info.Gpus | Where-Object { $_.IsDiscrete })
        if (-not $Info.IsLaptop -and $discrete.Count -gt 0) {
            $onIgpu = @($displays | Where-Object { -not (Test-DiscreteGpuName $_.Adapter) })
            if ($onIgpu.Count -gt 0) {
                Write-Check 'warn' 'Écran branché sur la carte mère' 'Branche le câble sur la carte graphique, pas sur la carte mère'
            } else {
                Write-Check 'ok' 'Écran branché sur la carte graphique'
            }
        }
    } catch {
        Write-Check 'info' 'Écrans : vérification impossible'
    }

    # GPU driver and PCIe link
    foreach ($gpu in $Info.Gpus) {
        if ($gpu.IsBasic) {
            Write-Check 'warn' "Pilote graphique de base Microsoft ($($gpu.Name))" 'Installe le pilote NVIDIA App ou AMD Adrenalin'
            continue
        }
        if (-not $gpu.IsDiscrete) { continue }
        Write-Check 'ok' "Pilote constructeur : $($gpu.Name)"
        $issue = Get-PciLinkIssue $gpu.PnpId
        if ($null -eq $issue) {
            Write-Check 'info' 'Largeur du lien PCIe : non vérifiable'
        } elseif ($issue) {
            Write-Check 'warn' "Carte graphique en $issue" 'Un SSD M.2 partage peut-être les lignes du GPU : vérifie le manuel de la carte mère'
        } else {
            Write-Check 'ok' 'Carte graphique en pleine largeur PCIe'
        }
    }

    # Intel 13th/14th gen desktop microcode
    if ($Info.CpuName -match 'i[3579]-1[34]\d00(K|KF|F|KS|T)?\b') {
        $raw = Get-RegValue 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' 'Update Revision'
        if ($raw -and $raw.Length -ge 8) {
            $revision = [BitConverter]::ToUInt32($raw, 4)
            if ($revision -lt 0x12B) {
                Write-Check 'warn' ('Microcode Intel 0x{0:X} trop ancien' -f $revision) 'Mets à jour le BIOS (correctif de dégradation des 13e/14e génération)'
            } else {
                Write-Check 'ok' ('Microcode Intel à jour (0x{0:X})' -f $revision)
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Flows
# ---------------------------------------------------------------------------

function Invoke-AllOptimizations($Info, $Choices) {
    Invoke-PrivacySteps $Info
    Invoke-AiSteps
    Invoke-SystemSteps $Info $Choices
    Invoke-PowerSteps $Info
    Invoke-GamingSteps
    Invoke-SearchSteps
    Invoke-EdgeSteps
    Invoke-InterfaceSteps
}

function Write-Summary {
    Write-Host ''
    if ($script:Failures.Count -eq 0) {
        Write-Host '  Toutes les étapes ont réussi.' -ForegroundColor Green
    } else {
        Write-Host ("  {0} étape(s) en échec : {1}" -f $script:Failures.Count, ($script:Failures -join ', ')) -ForegroundColor Red
    }
    foreach ($step in $script:ManualSteps) {
        Write-Host "  À faire à la main : $step" -ForegroundColor Yellow
    }
    Write-Host "  Journal : $LogPath" -ForegroundColor DarkGray
}

function Confirm-Hardware($Info) {
    Write-Title
    Write-Host '  Matériel détecté'
    Write-Host ''
    Write-Host ('  CPU      ' + $Info.CpuName)
    Write-Host ('  GPU      ' + (Get-GpuSummary $Info))
    Write-Host ('  RAM      {0} Go' -f $Info.RamGB)
    $type = if ($Info.IsVM) { 'Machine virtuelle' } elseif ($Info.IsLaptop) { 'Portable' } else { 'PC fixe' }
    Write-Host ('  Type     ' + $type)
    Write-Host ('  Windows  {0} (build {1})' -f $Info.Edition, $Info.Build)
    Wait-Key

    if (Read-YesNo 'Ces informations sont-elles correctes ?' $true) { return $Info }

    $cpuIndex = Read-Menu -Header 'Marque du processeur ?' -Items @(@{ Label = 'AMD' }, @{ Label = 'Intel' })
    $Info.CpuVendor = @('AMD', 'Intel')[$cpuIndex]
    if ($Info.CpuVendor -eq 'AMD') {
        $Info.IsDualCcdX3D = Read-YesNo 'Est-ce un X3D à deux CCD (7900X3D, 7950X3D, 9900X3D, 9950X3D) ?' $false
    } else {
        $Info.IsDualCcdX3D = $false
    }
    $Info.IsLaptop = ((Read-Menu -Header 'Type de PC ?' -Items @(@{ Label = 'PC fixe' }, @{ Label = 'Portable' })) -eq 1)
    return $Info
}

function Start-FirstRun($Info) {
    $Info = Confirm-Hardware $Info

    $items = @(
        @{ Label = 'Services Xbox (Game Pass, app Xbox, Game Bar)'; Value = $false
           Hint = 'Décoché : applis Xbox supprimées (réversible depuis le menu). Les manettes continuent de fonctionner.' },
        @{ Label = 'Impression'; Value = $false
           Hint = 'Décoché : spouleur et imprimantes virtuelles désactivés (réversible).' },
        @{ Label = 'WSL / Virtualisation'; Value = $false
           Hint = 'Décoché : Docker Desktop, WSL2 et les émulateurs Android ne fonctionneront plus (réversible).' },
        @{ Label = 'Installer Steam'; Value = $true
           Hint = 'Installé via winget, sans lancement au démarrage.' },
        @{ Label = 'Installer Discord'; Value = $true
           Hint = 'Installé via winget, sans lancement au démarrage.' }
    )
    $items = Read-Checkboxes -Header 'Coche ce que tu utilises (Firefox + uBlock Origin, VLC et 7-Zip sont installés d''office)' -Items $items

    $choices = [ordered]@{
        Xbox           = [bool]$items[0].Value
        KeepGameBar    = $false
        Printing       = [bool]$items[1].Value
        Virtualization = [bool]$items[2].Value
        Steam          = [bool]$items[3].Value
        Discord        = [bool]$items[4].Value
    }

    if (-not $choices.Xbox -and $Info.IsDualCcdX3D) {
        $choices.KeepGameBar = Read-YesNo ('Ton {0} utilise la Game Bar pour envoyer les jeux sur le bon CCD. La conserver ?' -f $Info.CpuName) $true
    }

    Write-Title
    Write-Host '  Récapitulatif'
    Write-Host ''
    $label = { param($keep) if ($keep) { 'conservé' } else { 'désactivé (réversible)' } }
    Write-Host ('  Xbox                  ' + (& $label $choices.Xbox)) -NoNewline
    if ($choices.KeepGameBar) { Write-Host ' - Game Bar conservée' } else { Write-Host '' }
    Write-Host ('  Impression            ' + (& $label $choices.Printing))
    Write-Host ('  WSL / Virtualisation  ' + (& $label $choices.Virtualization))
    Write-Host ('  Steam                 ' + $(if ($choices.Steam) { 'installé' } else { 'non installé' }))
    Write-Host ('  Discord               ' + $(if ($choices.Discord) { 'installé' } else { 'non installé' }))
    Wait-Key

    if (-not (Read-YesNo 'Lancer l''optimisation ?' $true)) { Wait-Exit 'Rien n''a été modifié.' }

    Write-OwLog ("Démarrage installation complète v{0} - {1}" -f $ScriptVersion, ($choices | ConvertTo-Json -Compress))
    Write-Title
    Invoke-AllOptimizations $Info $choices
    Invoke-ModuleChoices $Info $choices
    Invoke-AppSteps $choices
    Invoke-NotificationSteps
    Invoke-CleanupSteps

    Save-State ([ordered]@{
        Version          = $ScriptVersion
        InstallCompleted = $true
        CompletedAt      = (Get-Date).ToString('s')
        Choices          = $choices
    })

    Show-HealthCheck $Info
    Write-Summary

    Write-Host ''
    Write-Host '  Dernière étape : choisis Firefox et VLC comme applications par défaut.' -ForegroundColor Cyan
    Write-Host '  La page des Paramètres va s''ouvrir.' -ForegroundColor Cyan
    Wait-Key
    Start-Process 'ms-settings:defaultapps'

    Wait-Exit 'Redémarre le PC pour appliquer tous les réglages.'
}

function Invoke-Reapply($Info, $State) {
    $choices = [ordered]@{
        Xbox           = Get-XboxEnabled
        KeepGameBar    = [bool]$State.Choices.KeepGameBar
        Printing       = Get-PrintingEnabled
        Virtualization = Get-VirtualizationEnabled
    }
    Write-OwLog "Réapplication des optimisations v$ScriptVersion"
    Write-Title
    Invoke-AllOptimizations $Info $choices
    Write-Section 'Modules'
    if (-not $choices.Xbox) { Disable-Xbox -KeepGameBar $choices.KeepGameBar }
    Write-Section 'Applications'
    Invoke-Step 'Firefox : uBlock Origin et confidentialité' { Set-FirefoxPolicies }
    Invoke-Step 'Raccourcis Bureau inutiles' { Remove-Shortcut @('Microsoft Edge.lnk', 'VLC media player.lnk') }
    Invoke-NotificationSteps
    Invoke-CleanupSteps
    Write-Summary
    Wait-Key 'Redémarre le PC pour appliquer tous les réglages. Appuie sur une touche pour revenir au menu.'
}

function Invoke-ModuleToggle([string]$Name, [bool]$Enabled, [scriptblock]$OnDisable, [scriptblock]$OnEnable, [string]$Warning) {
    $action = if ($Enabled) { 'désactiver' } else { 'réactiver' }
    $question = "Module $Name : actuellement $(if ($Enabled) { 'activé' } else { 'désactivé' }). Le $action ?"
    if ($Warning -and $Enabled) { $question += "`n  $Warning" }
    if (-not (Read-YesNo $question $true)) { return }
    Write-Title
    Write-OwLog "Module $Name : $action"
    if ($Enabled) { & $OnDisable } else { & $OnEnable }
    Write-Summary
    Wait-Key 'Redémarrage recommandé. Appuie sur une touche pour revenir au menu.'
}

function Start-MainMenu($Info, $State) {
    while ($true) {
        Write-Title
        Write-Host '  Lecture de l''état du système...' -ForegroundColor DarkGray
        $xbox = Get-XboxEnabled
        $printing = Get-PrintingEnabled
        $virtualization = Get-VirtualizationEnabled
        $oneDrive = Get-OneDriveInstalled

        $status = { param($on) if ($on) { 'activé' } else { 'désactivé' } }
        $color = { param($on) if ($on) { 'Green' } else { 'DarkGray' } }
        $items = @(
            @{ Label = 'Xbox'; Status = (& $status $xbox); StatusColor = (& $color $xbox)
               Hint = 'App Xbox, Game Pass et Game Bar.' },
            @{ Label = 'Impression'; Status = (& $status $printing); StatusColor = (& $color $printing)
               Hint = 'Spouleur d''impression et imprimantes virtuelles PDF/XPS.' },
            @{ Label = 'WSL / Virtualisation'; Status = (& $status $virtualization); StatusColor = (& $color $virtualization)
               Hint = 'Nécessaire pour Docker Desktop, WSL2 et les émulateurs Android.' },
            @{ Label = 'OneDrive'; Status = (& $status $oneDrive); StatusColor = (& $color $oneDrive)
               Hint = 'Synchronisation de fichiers Microsoft.' },
            @{ Label = 'Bilan de santé'; SpaceBefore = $true; Hint = 'Vérifie BIOS, RAM, écran et carte graphique (lecture seule).' },
            @{ Label = 'Réappliquer les optimisations'; Hint = 'À relancer après une mise à jour majeure de Windows.' },
            @{ Label = 'Quitter'; SpaceBefore = $true }
        )

        $choice = Read-Menu -Items $items
        $script:Failures.Clear(); $script:ManualSteps.Clear()
        switch ($choice) {
            0 {
                $keepGameBar = $false
                if ($xbox -and $Info.IsDualCcdX3D) {
                    $keepGameBar = Read-YesNo 'Ton processeur utilise la Game Bar pour envoyer les jeux sur le bon CCD. La conserver ?' $true
                }
                Invoke-ModuleToggle 'Xbox' $xbox { Disable-Xbox -KeepGameBar $keepGameBar } { Enable-Xbox } ''
            }
            1 { Invoke-ModuleToggle 'Impression' $printing { Disable-Printing } { Enable-Printing } '' }
            2 { Invoke-ModuleToggle 'WSL / Virtualisation' $virtualization { Disable-Virtualization } { Enable-Virtualization } 'Docker Desktop, WSL2 et les émulateurs Android ne fonctionneront plus.' }
            3 { Invoke-ModuleToggle 'OneDrive' $oneDrive { Disable-OneDrive } { Enable-OneDrive } '' }
            4 { Write-Title; Show-HealthCheck $Info; Wait-Key }
            5 { if (Read-YesNo 'Réappliquer toutes les optimisations ?' $true) { Invoke-Reapply $Info $State } }
            6 { exit }
        }
    }
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

Write-OwLog ("config.ps1 v{0} lancé depuis {1}" -f $ScriptVersion, $PSCommandPath)
Write-Title
Write-Host '  Détection du matériel...' -ForegroundColor DarkGray
$systemInfo = Get-SystemInfo
Write-OwLog ("Système : " + ($systemInfo | Select-Object CpuName, CpuVendor, IsDualCcdX3D, RamGB, IsLaptop, IsVM, HasLinux, Edition, Build | ConvertTo-Json -Compress))

$state = Get-State
if ($null -eq $state -or -not $state.InstallCompleted) {
    Start-FirstRun $systemInfo
} else {
    Start-MainMenu $systemInfo $state
}
