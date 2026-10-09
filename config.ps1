#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 11 optimization - post-installation script.

.DESCRIPTION
    Installs the base applications, applies the privacy, performance and debloat
    settings of the InstallationWindows guide, manages the reversible modules
    (Xbox, printing, WSL/virtualization, OneDrive) and runs a read-only health
    check of the hardware configuration.

    Usage: copy this file to the Desktop, right-click > "Run with PowerShell".
    The script elevates itself. It is safe to run again at any time.

    This file is intentionally ASCII-only so it displays correctly whatever the
    encoding used to read it.
#>

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$MinBuild      = 26100
$DataDir       = Join-Path $env:ProgramData 'OptimisationWindows'
$StatePath     = Join-Path $DataDir 'state.json'
$TaskbarXml    = Join-Path $DataDir 'TaskbarLayout.xml'

$SchemeBalanced        = '381b4222-f694-41f0-9685-ff5bb260df2e'
$OverlayBestPerf       = 'ded574b5-45a0-4f42-8737-46345c09c238'
$NullPersistentHandler = '{098f2470-bae0-11cd-b579-08002b30bfeb}'

# Services that run by default on a clean install and are useless here.
# Rule: only services that are actually running on a fresh Windows 26H2.
$ServicesToDisable = @(
    'DiagTrack',      # Connected User Experiences and Telemetry
    'WSAIFabricSvc',  # Windows AI components host (Recall, Click to Do, Settings agent are disabled)
    'TrkWks',         # Distributed Link Tracking Client (NTFS links across networked PCs)
    'LanmanServer'    # Server (SMB file sharing from this PC; reading shares elsewhere still works)
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
    'Xbox'          = '9MV0B5HZVK9Z'
    'Xbox Game Bar' = '9NZKPSTSNW4P'
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
    Write-Host '  Press Enter to close.' -ForegroundColor DarkGray
    [void](Read-Host)
    exit
}

if (-not $PSCommandPath) {
    Wait-Exit 'Run this script from the config.ps1 file (right-click > Run with PowerShell).'
}

# Always run in an elevated Windows PowerShell 5.1 (Appx and DISM cmdlets need it).
if (-not (Test-Admin) -or $PSVersionTable.PSEdition -eq 'Core') {
    $argList = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    try {
        $verb = if (Test-Admin) { 'Open' } else { 'RunAs' }
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $argList -Verb $verb | Out-Null
    } catch {
        Wait-Exit 'Administrator rights are required. Run the script again and accept the prompt.'
    }
    exit
}

$Host.UI.RawUI.WindowTitle = 'Windows Optimization'

# QuickEdit: a click in the window starts a selection that freezes all output until Enter is pressed.
# Turn it off for this window only (the user's console defaults are not touched).
try {
    Add-Type -Namespace OwNative -Name Console -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
    $stdIn = [OwNative.Console]::GetStdHandle(-10)
    $mode = [uint32]0
    if ([OwNative.Console]::GetConsoleMode($stdIn, [ref]$mode)) {
        # Clear ENABLE_QUICK_EDIT_MODE (0x40), keep ENABLE_EXTENDED_FLAGS (0x80) so the change applies.
        [void][OwNative.Console]::SetConsoleMode($stdIn, [uint32](($mode - ($mode -band 0x40)) -bor 0x80))
    }
} catch { $null = $_ }

if ([Environment]::OSVersion.Version.Build -lt $MinBuild) {
    Wait-Exit ('Windows 11 24H2 or newer is required (build {0} detected, {1} minimum).' -f [Environment]::OSVersion.Version.Build, $MinBuild)
}

if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -Path $DataDir -ItemType Directory -Force | Out-Null }

# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

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
        throw ('{0} {1} failed (code {2}): {3}' -f $File, ($Arguments -join ' '), $LASTEXITCODE, $output.Trim())
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

function Clear-KeyBuffer {
    # Drop keys pressed before a prompt (e.g. Enter from the launch or the UAC prompt).
    while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
}

function Write-Title {
    Clear-Host
    Write-Host ''
    Write-Host '  Windows Optimization' -ForegroundColor White
    Write-Host ''
}

function Write-Section([string]$Title) {
    Write-Host ''
    Write-Host "  $Title" -ForegroundColor White
}

function Wait-Key([string]$Message = 'Press any key to continue...') {
    Write-Host ''
    Write-Host "  $Message" -ForegroundColor DarkGray
    Clear-KeyBuffer
    [void][Console]::ReadKey($true)
}

# Generic arrow-key menu. Header: lines printed above the items.
# Items: hashtables with Label, optional Status, StatusColor, Hint and SpaceBefore.
# Returns the selected index.
function Read-Menu {
    param([string[]]$Header, [object[]]$Items, [int]$Default = 0)
    $index = $Default
    Clear-KeyBuffer
    while ($true) {
        Write-Title
        if ($Header) {
            foreach ($line in $Header) { Write-Host "  $line" }
            Write-Host ''
        }
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            if ($item.SpaceBefore) { Write-Host '' }
            $selected = ($i -eq $index)
            $prefix = if ($selected) { '  > ' } else { '    ' }
            $color = if ($selected) { 'Cyan' } else { 'Gray' }
            Write-Host ($prefix + ([string]$item.Label).PadRight(32)) -ForegroundColor $color -NoNewline
            if ($item.Status) {
                $statusColor = if ($item.StatusColor) { $item.StatusColor } else { 'DarkGray' }
                Write-Host $item.Status -ForegroundColor $statusColor
            } else {
                Write-Host ''
            }
        }
        Write-Host ''
        if ($Items[$index].Hint) { Write-Host ('  ' + $Items[$index].Hint) -ForegroundColor Yellow }
        Write-Host '  Up/Down: move   Enter: select' -ForegroundColor DarkGray
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $index = ($index - 1 + $Items.Count) % $Items.Count }
            'DownArrow' { $index = ($index + 1) % $Items.Count }
            'Enter'     { return $index }
        }
    }
}

function Read-YesNo([string[]]$Header, [bool]$Default = $true) {
    $items = @(@{ Label = 'Yes' }, @{ Label = 'No' })
    $defaultIndex = if ($Default) { 0 } else { 1 }
    return ((Read-Menu -Header $Header -Items $items -Default $defaultIndex) -eq 0)
}

# Checkbox list. Items: hashtables with Label, Hint, Value (bool). Returns the items.
function Read-Checkboxes {
    param([string[]]$Header, [object[]]$Items)
    $index = 0
    Clear-KeyBuffer
    while ($true) {
        Write-Title
        if ($Header) {
            foreach ($line in $Header) { Write-Host "  $line" }
            Write-Host ''
        }
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
        Write-Host '  Up/Down: move   Space: check/uncheck   Enter: confirm' -ForegroundColor DarkGray
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

function Skip([string]$Reason) { return "__SKIP__$Reason" }

function Invoke-Step {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][scriptblock]$Action)
    Write-Host ("  ...  $Label") -ForegroundColor DarkGray -NoNewline
    $ErrorActionPreference = 'Stop'
    try {
        $result = @(& $Action)
        $skip = $result | Where-Object { $_ -is [string] -and $_.StartsWith('__SKIP__') } | Select-Object -First 1
        if ($skip) {
            Write-Host ("`r  --   $Label ({0})" -f $skip.Substring(8)) -ForegroundColor DarkGray
        } else {
            Write-Host ("`r  OK   $Label") -ForegroundColor Green
        }
    } catch {
        Write-Host ("`r  !!   $Label") -ForegroundColor Red
        Write-Host ("       {0}" -f $_.Exception.Message) -ForegroundColor DarkRed
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
    return 'Other'
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
            IsBasic    = ($_.PNPDeviceID -match 'BasicDisplay' -or $_.Name -match 'Basic Display')
        }
    })

    $cpuVendor = switch -Regex ($cpu.Manufacturer) {
        'AMD'   { 'AMD'; break }
        'Intel' { 'Intel'; break }
        default { 'Other' }
    }

    $ramBytes = (Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    $ramGB = [math]::Round($ramBytes / 1GB)

    $isVm = ($cs.Manufacturer -match 'QEMU|VMware|innotek|Xen|Parallels') -or
            ($cs.Model -match 'Virtual|KVM|VMware|VirtualBox|Q35|i440FX')

    $hasLinux = [bool](Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.GptType -eq '{0FC63DAF-8483-4772-8E79-3D69D8477DE4}' })

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

function Get-XboxEnabled {
    # The Game Bar alone does not count: Windows may protect it, or it is kept for dual-CCD X3D CPUs.
    return [bool](Get-AppxPackage -Name 'Microsoft.GamingApp' -ErrorAction SilentlyContinue)
}

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
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction SilentlyContinue
    return [bool](Get-Command -Name 'winget' -ErrorAction SilentlyContinue)
}

function Test-WingetInstalled([string]$Id, [string]$Source = 'winget') {
    $ErrorActionPreference = 'Continue'
    & winget list --id $Id --exact --source $Source --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-WingetPackage([string]$Id, [string]$Source = 'winget') {
    if (Test-WingetInstalled -Id $Id -Source $Source) { return (Skip 'already installed') }
    $arguments = @('install', '--id', $Id, '--exact', '--source', $Source, '--silent',
                   '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    Invoke-Native -File 'winget' -Arguments $arguments | Out-Null
}

function Uninstall-WingetPackage([string]$Id) {
    if (-not (Test-WingetInstalled -Id $Id)) { return (Skip 'not installed') }
    Invoke-Native -File 'winget' -Arguments @('uninstall', '--id', $Id, '--exact', '--silent', '--accept-source-agreements', '--disable-interactivity') | Out-Null
}

# ---------------------------------------------------------------------------
# Applications
# ---------------------------------------------------------------------------

function Set-FirefoxConfig {
    $firefoxDir = Join-Path $env:ProgramFiles 'Mozilla Firefox'
    if (-not (Test-Path -LiteralPath (Join-Path $firefoxDir 'firefox.exe'))) { return (Skip 'Firefox not found') }
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    # Preferences through AutoConfig instead of enterprise policies: no "managed by your
    # organization" banner, and these are only defaults the user can still change.
    $prefDir = Join-Path $firefoxDir 'defaults\pref'
    New-Item -Path $prefDir -ItemType Directory -Force | Out-Null
    $autoconfig = 'pref("general.config.filename", "firefox.cfg");' + "`n" + 'pref("general.config.obscure_value", 0);' + "`n"
    [IO.File]::WriteAllText((Join-Path $prefDir 'autoconfig.js'), $autoconfig, $utf8)
    $cfg = @'
// Defaults set by config.ps1 (this first line is ignored by Firefox)
defaultPref("datareporting.policy.dataSubmissionEnabled", false);
defaultPref("datareporting.healthreport.uploadEnabled", false);
defaultPref("app.shield.optoutstudies.enabled", false);
defaultPref("browser.newtabpage.activity-stream.feeds.topsites", false);
defaultPref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
'@
    [IO.File]::WriteAllText((Join-Path $firefoxDir 'firefox.cfg'), $cfg, $utf8)

    # uBlock Origin: Firefox installs the extensions of distribution\extensions in every new profile.
    $extDir = Join-Path $firefoxDir 'distribution\extensions'
    $xpi = Join-Path $extDir 'uBlock0@raymondhill.net.xpi'
    if (-not (Test-Path -LiteralPath $xpi)) {
        New-Item -Path $extDir -ItemType Directory -Force | Out-Null
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri 'https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi' -OutFile $xpi -UseBasicParsing
    }

    # Daily task that reports the default browser to Mozilla.
    Get-ScheduledTask -TaskPath '\Mozilla\' -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -like 'Firefox Default Browser Agent*' } | Disable-ScheduledTask | Out-Null
}

function Add-FirefoxToTaskbar {
    # Windows 11 has no API to pin apps: apply a taskbar layout once through the
    # Explorer policy (same mechanism as the unattended setup), then unlock it so
    # the user stays free to change the pins.
    $link = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Firefox.lnk'
    if (-not (Test-Path -LiteralPath $link)) { return (Skip 'Firefox shortcut not found') }
    $xml = @'
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer"/>
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Firefox.lnk"/>
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
'@
    [IO.File]::WriteAllText($TaskbarXml, $xml, (New-Object System.Text.UTF8Encoding($false)))
    $key = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    Set-RegValue $key 'StartLayoutFile' $TaskbarXml 'ExpandString'
    Set-RegValue $key 'LockedStartLayout' 1
    Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 6
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) { Start-Process 'explorer.exe' }
    Start-Sleep -Seconds 4
    Set-RegValue $key 'LockedStartLayout' 0
}

function Disable-StartupEntry([string]$Name) {
    # Same flag Task Manager writes when an entry is disabled (03 + timestamp).
    $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTimeUtc()))
    Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' $Name $bytes 'Binary'
}

function Invoke-AppSteps($Choices) {
    Write-Section 'Applications'

    if (-not (Initialize-Winget)) {
        Invoke-Step 'winget' { throw 'winget not found: update "App Installer" from the Microsoft Store, then run the script again.' }
        return
    }

    Invoke-Step 'Firefox' { Install-WingetPackage 'Mozilla.Firefox.fr' }
    Invoke-Step 'Firefox: uBlock Origin and settings' { Set-FirefoxConfig }
    Invoke-Step 'Firefox: pin to the taskbar' { Add-FirefoxToTaskbar }
    Invoke-Step 'VLC' {
        $result = Install-WingetPackage 'VideoLAN.VLC'
        Remove-Shortcut @('VLC media player.lnk')
        $result
    }
    Invoke-Step '7-Zip' { Install-WingetPackage '7zip.7zip' }

    if ($Choices.Steam) {
        Invoke-Step 'Steam' { Install-WingetPackage 'Valve.Steam' }
        Invoke-Step 'Steam: no launch at startup' { Disable-StartupEntry 'Steam' }
    }
    if ($Choices.Discord) {
        Invoke-Step 'Discord' { Install-WingetPackage 'Discord.Discord' }
        Invoke-Step 'Discord: no launch at startup' { Disable-StartupEntry 'Discord' }
    }
}

# ---------------------------------------------------------------------------
# Optimizations (no rollback)
# ---------------------------------------------------------------------------

function Invoke-PrivacySteps($Info) {
    Write-Section 'Privacy and telemetry'

    Invoke-Step 'Telemetry and useless services' {
        foreach ($name in $ServicesToDisable) { [void](Set-ServiceStartup -Name $name -Startup Disabled -Stop) }
    }

    Invoke-Step 'Telemetry scheduled tasks' {
        foreach ($task in $TelemetryTasks) { Disable-TaskByPath $task }
    }

    Invoke-Step 'Windows Error Reporting' {
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    }

    Invoke-Step 'PowerShell telemetry' {
        [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
    }

    Invoke-Step 'Advertising ID and tailored experiences' {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0
    }

    Invoke-Step 'Inking and typing personalization' {
        Set-RegValue 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
        Set-RegValue 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
        Set-RegValue 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
    }

    Invoke-Step 'Location' {
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
    }

    Invoke-Step 'Feedback requests' {
        Set-RegValue 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
    }

    Invoke-Step 'Web and cloud results in Start search' {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsMSACloudSearchEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsAADCloudSearchEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDeviceSearchHistoryEnabled' 0
    }

    Invoke-Step 'Defender: no automatic sample submission' {
        if (-not (Get-Command -Name 'Set-MpPreference' -ErrorAction SilentlyContinue)) { return (Skip 'Defender not available') }
        Set-MpPreference -SubmitSamplesConsent 2
    }

    if ($Info.HasNvidia) {
        Invoke-Step 'NVIDIA telemetry' {
            Set-RegValue 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0
            Get-ScheduledTask -TaskName 'NvTm*' -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
        }
    }
}

function Invoke-AiSteps {
    Write-Section 'AI and Copilot'

    Invoke-Step 'Copilot' {
        Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    }

    Invoke-Step 'Recall, Click to Do and Settings agent' {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
        Set-RegValue $key 'DisableAIDataAnalysis' 1
        Set-RegValue $key 'AllowRecallEnablement' 0
        Set-RegValue $key 'DisableClickToDo' 1
        Set-RegValue $key 'DisableSettingsAgent' 1
        Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    }

    Invoke-Step 'AI in Notepad and Paint' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1
        $paint = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'
        Set-RegValue $paint 'DisableCocreator' 1
        Set-RegValue $paint 'DisableGenerativeFill' 1
        Set-RegValue $paint 'DisableImageCreator' 1
    }
}

function Invoke-SystemSteps($Info, $Choices) {
    Write-Section 'System and services'

    Invoke-Step 'SysMain' {
        if ($Info.RamGB -lt 32) { return (Skip ('kept, {0} GB of RAM' -f $Info.RamGB)) }
        [void](Set-ServiceStartup -Name 'SysMain' -Startup Disabled -Stop)
    }

    Invoke-Step 'Hibernation' {
        Invoke-Native -File 'powercfg.exe' -Arguments @('/hibernate', 'off') | Out-Null
    }

    Invoke-Step 'Background apps' {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
        $allowed = @('Microsoft.SecHealthUI_8wekyb3d8bbwe')
        if ($Choices.Xbox) { $allowed += 'Microsoft.GamingApp_8wekyb3d8bbwe', 'Microsoft.XboxGamingOverlay_8wekyb3d8bbwe' }
        Set-RegValue $key 'LetAppsRunInBackground' 2
        Set-RegValue $key 'LetAppsRunInBackground_ForceAllowTheseApps' ([string[]]$allowed) 'MultiString'
    }

    Invoke-Step 'Peer-to-peer update sharing' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    }

    Invoke-Step 'Remote Assistance' {
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
    }

    Invoke-Step 'Cross-device resume and connected devices' {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        Set-RegValue $key 'EnableCdp' 0
        Set-RegValue $key 'EnableActivityFeed' 0
        Set-RegValue $key 'PublishUserActivities' 0
        Set-RegValue $key 'UploadUserActivities' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration' 'IsResumeAllowed' 0
    }

    Invoke-Step 'Windows Update active hours (8:00 - 2:00)' {
        $key = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        Set-RegValue $key 'SmartActiveHoursState' 0
        Set-RegValue $key 'ActiveHoursStart' 8
        Set-RegValue $key 'ActiveHoursEnd' 2
    }

    Invoke-Step 'No automatic sign-in after an update' {
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableAutomaticRestartSignOn' 1
    }

    Invoke-Step 'Linux-compatible clock (dual boot)' {
        if (-not $Info.HasLinux) { return (Skip 'no Linux partition') }
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' 'RealTimeIsUniversal' 1
    }
}

function Invoke-PowerSteps($Info) {
    Write-Section 'Power and latency'

    if ($Info.IsLaptop) {
        Invoke-Step 'Power settings' { return (Skip 'laptop, left to the manufacturer') }
        return
    }

    Invoke-Step 'Balanced plan + "Best performance" power mode' {
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setactive', $SchemeBalanced) | Out-Null
        try {
            Invoke-Native -File 'powercfg.exe' -Arguments @('/overlaysetactive', $OverlayBestPerf) | Out-Null
        } catch {
            $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
            Set-RegValue $key 'ActiveOverlayAcPowerScheme' $OverlayBestPerf 'String'
            Set-RegValue $key 'ActiveOverlayDcPowerScheme' $OverlayBestPerf 'String'
        }
    }

    Invoke-Step 'PCI Express link state power management' {
        if ($Info.HasDiscreteArc) { return (Skip 'Intel Arc GPU, kept') }
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setacvalueindex', $SchemeBalanced, 'SUB_PCIEXPRESS', 'ASPM', '0') | Out-Null
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setdcvalueindex', $SchemeBalanced, 'SUB_PCIEXPRESS', 'ASPM', '0') | Out-Null
    }

    Invoke-Step 'USB selective suspend' {
        $sub = '2a737441-1930-4402-8d77-b2bebba308a3'; $setting = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setacvalueindex', $SchemeBalanced, $sub, $setting, '0') | Out-Null
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setdcvalueindex', $SchemeBalanced, $sub, $setting, '0') | Out-Null
    }

    Invoke-Step 'Wi-Fi power saving' {
        $sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'; $setting = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setacvalueindex', $SchemeBalanced, $sub, $setting, '0') | Out-Null
    }

    Invoke-Step 'Apply the modified power plan' {
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setactive', $SchemeBalanced) | Out-Null
    }

    Invoke-Step 'Network adapter power saving' {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
        if ($adapters.Count -eq 0) { return (Skip 'no adapter found') }
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
            # "Allow the computer to turn off this device to save power" (Device Manager checkbox).
            $pnpId = [string]$adapter.PnPDeviceID
            $power = @(Get-CimInstance -Namespace 'root\wmi' -ClassName 'MSPower_DeviceEnable' -ErrorAction SilentlyContinue |
                Where-Object { $pnpId -and $_.InstanceName.StartsWith($pnpId, [StringComparison]::OrdinalIgnoreCase) })
            foreach ($entry in $power) {
                if ($entry.Enable) { Set-CimInstance -InputObject $entry -Property @{ Enable = $false } -ErrorAction SilentlyContinue }
            }
        }
    }
}

function Invoke-GamingSteps {
    Write-Section 'Gaming and display'

    Invoke-Step 'Optimizations for windowed games and VRR' {
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

    Invoke-Step 'Background recording (Game DVR)' {
        Set-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 0
    }
}

function Invoke-SearchSteps {
    Write-Section 'Search'

    Invoke-Step 'Document indexing: names and properties only' {
        foreach ($ext in $PropertiesOnlyExtensions) {
            $key = "HKLM:\SOFTWARE\Classes\$ext\PersistentHandler"
            $current = Get-RegValue $key '(default)'
            if ($current -eq $NullPersistentHandler) { continue }
            if ($current) { Set-RegValue $key 'OriginalPersistentHandler' $current 'String' }
            Set-RegValue $key '(default)' $NullPersistentHandler 'String'
        }
    }
}

function Invoke-EdgeSteps {
    Write-Section 'Microsoft Edge'

    Invoke-Step 'Edge in the background and startup boost' {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        Set-RegValue $key 'StartupBoostEnabled' 0
        Set-RegValue $key 'BackgroundModeEnabled' 0
        Set-RegValue $key 'HideFirstRunExperience' 1
        Set-RegValue $key 'HubsSidebarEnabled' 0
        Set-RegValue $key 'ShowRecommendationsEnabled' 0
        Set-RegValue $key 'SpotlightExperiencesAndRecommendationsEnabled' 0
        Set-RegValue $key 'DefaultBrowserSettingEnabled' 0
    }

    Invoke-Step 'Edge updates: daily check only' {
        Get-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachineUA*' -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
        [void](Set-ServiceStartup -Name 'edgeupdate' -Startup Manual)
        [void](Set-ServiceStartup -Name 'edgeupdatem' -Startup Manual)
    }

    Invoke-Step 'Edge desktop shortcut' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0
        Remove-Shortcut @('Microsoft Edge.lnk')
    }
}

function Invoke-InterfaceSteps {
    Write-Section 'Interface, keyboard and audio'

    Invoke-Step 'Windows Security icon in the taskbar' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray' 'HideSystray' 1
    }

    Invoke-Step 'Alt+Shift keyboard layout shortcut' {
        $key = 'HKCU:\Keyboard Layout\Toggle'
        Set-RegValue $key 'Hotkey' '3' 'String'
        Set-RegValue $key 'Language Hotkey' '3' 'String'
        Set-RegValue $key 'Layout Hotkey' '3' 'String'
    }

    Invoke-Step 'Accessibility shortcuts (sticky, filter and toggle keys)' {
        Set-RegValue 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
        Set-RegValue 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'
        Set-RegValue 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String'
    }

    Invoke-Step 'Autocorrect and misspelling highlight' {
        Set-RegValue 'HKCU:\Software\Microsoft\TabletTip\1.7' 'EnableAutocorrection' 0
        Set-RegValue 'HKCU:\Software\Microsoft\TabletTip\1.7' 'EnableSpellchecking' 0
    }

    Invoke-Step 'Volume reduction during calls' {
        Set-RegValue 'HKCU:\Software\Microsoft\Multimedia\Audio' 'UserDuckingPreference' 3
    }
}

function Invoke-NotificationSteps {
    Write-Section 'Notifications'

    Invoke-Step 'Notifications off' {
        # Same as Settings > System > Notifications > Notifications: Off (can be turned back on there).
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
    }
}

function Invoke-CleanupSteps {
    Write-Section 'Cleanup'

    Invoke-Step 'Temporary files' {
        foreach ($dir in @($env:TEMP, "$env:SystemRoot\Temp")) {
            Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Reversible modules
# ---------------------------------------------------------------------------

function Disable-Xbox([bool]$KeepGameBar = $false) {
    Invoke-Step 'Remove Xbox apps' {
        $targets = @($XboxPackages | Where-Object { -not ($KeepGameBar -and $_ -eq 'Microsoft.XboxGamingOverlay') })
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
        $protected = @()
        $errors = @{}
        foreach ($name in $targets) {
            # Deprovision first so the app is not installed again for new users.
            foreach ($package in @($provisioned | Where-Object { $_.DisplayName -eq $name })) {
                Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $package.PackageName -ErrorAction SilentlyContinue | Out-Null
            }
            foreach ($package in @(Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue)) {
                if ($package.NonRemovable) { $protected += $name; continue }
                # Fall back to the current user when the all-users removal is refused.
                try { Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop }
                catch {
                    try { Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop }
                    catch { $errors[$name] = $_.Exception.Message.Trim() }
                }
            }
        }
        $remaining = @($targets | Where-Object { $protected -notcontains $_ -and (Get-AppxPackage -Name $_ -ErrorAction SilentlyContinue) })
        if ($remaining.Count -gt 0) {
            throw ('still installed: ' + (($remaining | ForEach-Object { if ($errors[$_]) { '{0} ({1})' -f $_, $errors[$_] } else { $_ } }) -join '; '))
        }
        if ($protected.Count -gt 0) { return (Skip ('protected by Windows, kept: {0}' -f (($protected | Select-Object -Unique) -join ', '))) }
    }
}

function Enable-Xbox {
    if (-not (Initialize-Winget)) { Invoke-Step 'winget' { throw 'winget not found.' }; return }
    foreach ($entry in $XboxStoreIds.GetEnumerator()) {
        $id = $entry.Value
        Invoke-Step ('Install {0}' -f $entry.Key) { Install-WingetPackage -Id $id -Source 'msstore' }
    }
}

function Disable-Printing {
    Invoke-Step 'Print Spooler' { [void](Set-ServiceStartup -Name 'Spooler' -Startup Disabled -Stop) }
    Invoke-Step 'PDF and XPS virtual printers' {
        foreach ($feature in 'Printing-PrintToPDFServices-Features', 'Printing-XPSServices-Features') {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($f -and $f.State -eq 'Enabled') { Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null }
        }
    }
}

function Enable-Printing {
    Invoke-Step 'Print Spooler' { [void](Set-ServiceStartup -Name 'Spooler' -Startup Automatic -Start) }
    Invoke-Step 'PDF and XPS virtual printers' {
        foreach ($feature in 'Printing-PrintToPDFServices-Features', 'Printing-XPSServices-Features') {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($f -and $f.State -ne 'Enabled') { Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null }
        }
    }
}

function Disable-Virtualization {
    Invoke-Step 'WSL, virtualization platforms, Hyper-V and Sandbox' {
        foreach ($feature in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform', 'HypervisorPlatform', 'Microsoft-Hyper-V-All', 'Containers-DisposableClientVM') {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($f -and $f.State -eq 'Enabled') { Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null }
        }
    }
    Invoke-Step 'Hypervisor at boot' {
        Invoke-Native -File 'bcdedit.exe' -Arguments @('/set', 'hypervisorlaunchtype', 'off') | Out-Null
    }
}

function Enable-Virtualization {
    Invoke-Step 'WSL and virtualization platforms' {
        foreach ($feature in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform', 'HypervisorPlatform') {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($f -and $f.State -ne 'Enabled') { Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null }
        }
    }
    Invoke-Step 'Hypervisor at boot' {
        Invoke-Native -File 'bcdedit.exe' -Arguments @('/set', 'hypervisorlaunchtype', 'auto') | Out-Null
    }
}

function Enable-OneDrive {
    if (-not (Initialize-Winget)) { Invoke-Step 'winget' { throw 'winget not found.' }; return }
    Invoke-Step 'Install OneDrive' { Install-WingetPackage 'Microsoft.OneDrive' }
}

function Disable-OneDrive {
    if (-not (Initialize-Winget)) { Invoke-Step 'winget' { throw 'winget not found.' }; return }
    Invoke-Step 'Uninstall OneDrive' {
        Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Uninstall-WingetPackage 'Microsoft.OneDrive'
    }
}

function Invoke-ModuleChoices($Choices) {
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
        'ok'    { Write-Host '  OK   ' -ForegroundColor Green -NoNewline }
        'warn'  { Write-Host '  !!   ' -ForegroundColor Red -NoNewline }
        default { Write-Host '  i    ' -ForegroundColor Yellow -NoNewline }
    }
    Write-Host $Message
    if ($Advice) { Write-Host "       -> $Advice" -ForegroundColor DarkGray }
}

function Show-HealthCheck($Info) {
    Write-Section 'Health check'

    # VBS
    $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg -and $dg.VirtualizationBasedSecurityStatus -eq 2) {
        Write-Check 'warn' 'VBS / memory integrity still running' 'Windows Security > Device security > Core isolation: turn off, then restart'
    } else {
        Write-Check 'ok' 'VBS disabled'
    }

    if ($Info.IsVM) {
        Write-Check 'info' 'Virtual machine: graphics checks skipped'
        return
    }

    # Graphics driver
    foreach ($gpu in $Info.Gpus) {
        if ($gpu.IsBasic) {
            Write-Check 'warn' "Microsoft basic display driver ($($gpu.Name))" 'Install the driver with NVIDIA App or AMD Adrenalin'
        } elseif ($gpu.IsDiscrete) {
            Write-Check 'ok' "Graphics driver installed: $($gpu.Name)"
        }
    }

    # Refresh rate
    try {
        Initialize-DisplayHelper
        foreach ($d in [OwDisplayInfo]::Get()) {
            $label = 'Display {0}x{1} at {2} Hz' -f $d.Width, $d.Height, $d.CurrentHz
            if ($d.MaxHz -gt $d.CurrentHz) {
                Write-Check 'warn' $label ('{0} Hz available: Settings > System > Display > Advanced display' -f $d.MaxHz)
            } else {
                Write-Check 'ok' $label
            }
        }
    } catch {
        Write-Check 'info' 'Displays: cannot be checked'
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
        Write-Host '  All steps succeeded.' -ForegroundColor Green
    } else {
        Write-Host ('  {0} step(s) failed: {1}' -f $script:Failures.Count, ($script:Failures -join ', ')) -ForegroundColor Red
    }
}

function Confirm-Hardware($Info) {
    $type = if ($Info.IsVM) { 'Virtual machine' } elseif ($Info.IsLaptop) { 'Laptop' } else { 'Desktop' }
    $header = @(
        'Detected hardware',
        '',
        ('CPU      ' + $Info.CpuName),
        ('GPU      ' + (Get-GpuSummary $Info)),
        ('RAM      {0} GB' -f $Info.RamGB),
        ('Type     ' + $type),
        ('Windows  {0} (build {1})' -f $Info.Edition, $Info.Build),
        '',
        'Is this correct?'
    )
    if (Read-YesNo $header $true) { return $Info }

    $cpuIndex = Read-Menu -Header 'CPU brand?' -Items @(@{ Label = 'AMD' }, @{ Label = 'Intel' })
    $Info.CpuVendor = @('AMD', 'Intel')[$cpuIndex]
    if ($Info.CpuVendor -eq 'AMD') {
        $Info.IsDualCcdX3D = Read-YesNo 'Is it a dual-CCD X3D (7900X3D, 7950X3D, 9900X3D, 9950X3D)?' $false
    } else {
        $Info.IsDualCcdX3D = $false
    }
    $Info.IsLaptop = ((Read-Menu -Header 'Type of PC?' -Items @(@{ Label = 'Desktop' }, @{ Label = 'Laptop' })) -eq 1)
    return $Info
}

function Start-FirstRun($Info) {
    $Info = Confirm-Hardware $Info

    $items = @(
        @{ Label = 'Xbox (Game Pass, Xbox app, Game Bar)'; Value = $false
           Hint = 'Unchecked: Xbox apps removed (reversible from the menu). Controllers keep working.' },
        @{ Label = 'Printing'; Value = $false
           Hint = 'Unchecked: print spooler and virtual printers disabled (reversible).' },
        @{ Label = 'WSL / Virtualization'; Value = $false
           Hint = 'Unchecked: Docker Desktop, WSL2 and Android emulators will not work (reversible).' },
        @{ Label = 'Install Steam'; Value = $false
           Hint = 'Installed with winget, not launched at startup.' },
        @{ Label = 'Install Discord'; Value = $false
           Hint = 'Installed with winget, not launched at startup.' }
    )
    $items = Read-Checkboxes -Header 'Check what you use' -Items $items

    $choices = [ordered]@{
        Xbox           = [bool]$items[0].Value
        KeepGameBar    = $false
        Printing       = [bool]$items[1].Value
        Virtualization = [bool]$items[2].Value
        Steam          = [bool]$items[3].Value
        Discord        = [bool]$items[4].Value
    }

    if (-not $choices.Xbox -and $Info.IsDualCcdX3D) {
        $choices.KeepGameBar = Read-YesNo @(
            ('Your {0} uses the Game Bar to send games to the right CCD.' -f $Info.CpuName),
            'Keep the Game Bar?'
        ) $true
    }

    $label = { param($keep) if ($keep) { 'kept' } else { 'disabled (reversible)' } }
    $installed = { param($on) if ($on) { 'installed' } else { 'not installed' } }
    $xboxLine = 'Xbox                  ' + (& $label $choices.Xbox)
    if ($choices.KeepGameBar) { $xboxLine += ', Game Bar kept' }
    $summary = @(
        'Summary',
        '',
        $xboxLine,
        ('Printing              ' + (& $label $choices.Printing)),
        ('WSL / Virtualization  ' + (& $label $choices.Virtualization)),
        ('Steam                 ' + (& $installed $choices.Steam)),
        ('Discord               ' + (& $installed $choices.Discord)),
        '',
        'Start the optimization?'
    )
    if (-not (Read-YesNo $summary $true)) { Wait-Exit 'Nothing was changed.' }

    Write-Title
    Invoke-AppSteps $choices
    Invoke-AllOptimizations $Info $choices
    Invoke-ModuleChoices $choices
    Invoke-NotificationSteps
    Invoke-CleanupSteps

    Save-State ([ordered]@{ InstallCompleted = $true; Choices = $choices })

    Show-HealthCheck $Info
    Write-Summary
    Wait-Exit 'Restart the PC to apply all settings.'
}

function Invoke-Reapply($Info, $State) {
    $choices = [ordered]@{
        Xbox           = Get-XboxEnabled
        KeepGameBar    = [bool]$State.Choices.KeepGameBar
        Printing       = Get-PrintingEnabled
        Virtualization = Get-VirtualizationEnabled
    }
    Write-Title
    Invoke-AllOptimizations $Info $choices
    Write-Section 'Modules'
    if (-not $choices.Xbox) { Disable-Xbox -KeepGameBar $choices.KeepGameBar }
    Write-Section 'Applications'
    Invoke-Step 'Firefox: uBlock Origin and settings' { Set-FirefoxConfig }
    Invoke-NotificationSteps
    Invoke-CleanupSteps
    Write-Summary
    Wait-Key 'Restart the PC to apply all settings. Press any key to go back to the menu.'
}

function Invoke-ModuleToggle([string]$Name, [bool]$Enabled, [scriptblock]$OnDisable, [scriptblock]$OnEnable, [string]$Warning) {
    $state = if ($Enabled) { 'enabled' } else { 'disabled' }
    $action = if ($Enabled) { 'Disable' } else { 'Enable' }
    $header = @("$Name module: currently $state.")
    if ($Warning -and $Enabled) { $header += $Warning }
    $header += "$action it?"
    if (-not (Read-YesNo $header $true)) { return }
    Write-Title
    if ($Enabled) { & $OnDisable } else { & $OnEnable }
    Write-Summary
    Wait-Key 'Restart recommended. Press any key to go back to the menu.'
}

function Start-MainMenu($Info, $State) {
    while ($true) {
        Write-Title
        Write-Host '  Reading system state...' -ForegroundColor DarkGray
        $xbox = Get-XboxEnabled
        $printing = Get-PrintingEnabled
        $virtualization = Get-VirtualizationEnabled
        $oneDrive = Get-OneDriveInstalled

        $status = { param($on) if ($on) { 'enabled' } else { 'disabled' } }
        $color = { param($on) if ($on) { 'Green' } else { 'DarkGray' } }
        $items = @(
            @{ Label = 'Xbox'; Status = (& $status $xbox); StatusColor = (& $color $xbox)
               Hint = 'Xbox app, Game Pass and Game Bar.' },
            @{ Label = 'Printing'; Status = (& $status $printing); StatusColor = (& $color $printing)
               Hint = 'Print spooler and PDF/XPS virtual printers.' },
            @{ Label = 'WSL / Virtualization'; Status = (& $status $virtualization); StatusColor = (& $color $virtualization)
               Hint = 'Needed for Docker Desktop, WSL2 and Android emulators.' },
            @{ Label = 'OneDrive'; Status = (& $status $oneDrive); StatusColor = (& $color $oneDrive)
               Hint = 'Microsoft file sync.' },
            @{ Label = 'Health check'; SpaceBefore = $true; Hint = 'Checks VBS, graphics driver and display refresh rate (read only).' },
            @{ Label = 'Reapply optimizations'; Hint = 'Run it again after a major Windows update.' },
            @{ Label = 'Quit'; SpaceBefore = $true }
        )

        $choice = Read-Menu -Items $items
        $script:Failures.Clear()
        switch ($choice) {
            0 {
                $keepGameBar = $false
                if ($xbox -and $Info.IsDualCcdX3D) {
                    $keepGameBar = Read-YesNo @('Your CPU uses the Game Bar to send games to the right CCD.', 'Keep the Game Bar?') $true
                }
                Invoke-ModuleToggle 'Xbox' $xbox { Disable-Xbox -KeepGameBar $keepGameBar } { Enable-Xbox } ''
            }
            1 { Invoke-ModuleToggle 'Printing' $printing { Disable-Printing } { Enable-Printing } '' }
            2 { Invoke-ModuleToggle 'WSL / Virtualization' $virtualization { Disable-Virtualization } { Enable-Virtualization } 'Docker Desktop, WSL2 and Android emulators will stop working.' }
            3 { Invoke-ModuleToggle 'OneDrive' $oneDrive { Disable-OneDrive } { Enable-OneDrive } '' }
            4 { Write-Title; Show-HealthCheck $Info; Wait-Key }
            5 { if (Read-YesNo 'Reapply all optimizations?' $true) { Invoke-Reapply $Info $State } }
            6 { exit }
        }
    }
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

Write-Title
Write-Host '  Detecting hardware...' -ForegroundColor DarkGray
$systemInfo = Get-SystemInfo

$state = Get-State
if ($null -eq $state -or -not $state.InstallCompleted) {
    Start-FirstRun $systemInfo
} else {
    Start-MainMenu $systemInfo $state
}
