<# : batch portion
@echo off
rem setup.cmd is both a batch file and a PowerShell script: a double-click runs this part,
rem which hands the whole file to Windows PowerShell 5.1 (no execution policy involved).
setlocal EnableExtensions DisableDelayedExpansion
set "OW_SELF=%~f0"
rem Set only by the elevated restart of the script, so it never restarts itself in a loop.
set "OW_ELEVATED="
if /i "%~1"=="/elevated" set "OW_ELEVATED=1"
rem 64-bit PowerShell even when a 32-bit program starts this file (Sysnative only exists there).
set "OW_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "OW_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%OW_PS%" -NoProfile -Command ". ([scriptblock]::Create((Get-Content -LiteralPath $env:OW_SELF -Raw)))"
rem The script always ends with exit 0: any other code is a crash, keep its message on screen.
if errorlevel 1 pause
exit /b
#>

<#
.SYNOPSIS
    Windows 11 optimization - post-installation script.

.DESCRIPTION
    Installs the base applications if missing, applies the privacy, performance and
    debloat settings of the InstallationWindows guide, applies the changes checked in
    the list (Xbox, printing, WSL/virtualization, OneDrive, notifications...) and runs
    a read-only health check. Every run does the same thing: run it again after a
    major Windows update.

    Usage: double-click setup.cmd on the USB key. The script elevates itself, copies
    itself to C:\ProgramData\OptimisationWindows and creates the "Optimisation Windows"
    shortcut on the Desktop to run it again later.

    This file is intentionally ASCII-only with CRLF line endings: cmd.exe needs CRLF,
    and ASCII displays correctly whatever the encoding used to read it.
#>

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$MinBuild      = 26100
$DataDir       = Join-Path $env:ProgramData 'OptimisationWindows'
$TaskbarXml    = Join-Path $DataDir 'TaskbarLayout.xml'
$InstalledCopy = Join-Path $DataDir 'setup.cmd'
$ShortcutName  = 'Optimisation Windows.lnk'

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

# Apps removed by the USB key that Windows Update or the Store may install again.
$ReturningApps = [ordered]@{
    'Microsoft.OutlookForWindows'  = 'Outlook'
    'Microsoft.Copilot'            = 'Copilot'
    'Microsoft.MicrosoftOfficeHub' = 'Microsoft 365'
    'MSTeams'                      = 'Teams'
    'Microsoft.Windows.DevHome'    = 'Dev Home'
}

# Optional Windows features of the modules.
$PrintingFeatures      = @('Printing-PrintToPDFServices-Features', 'Printing-XPSServices-Features')
$VirtualizationEnable  = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform', 'HypervisorPlatform')
$VirtualizationDisable = $VirtualizationEnable + @('Microsoft-Hyper-V-All', 'Containers-DisposableClientVM')

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
    exit 0
}

# Path of setup.cmd, given by its batch part.
$SelfPath = $env:OW_SELF
if (-not $SelfPath -or -not (Test-Path -LiteralPath $SelfPath)) {
    Wait-Exit 'Run setup.cmd with a double-click.'
}

# Appx and DISM cmdlets need administrator rights: start setup.cmd again, elevated.
if (-not (Test-Admin)) {
    # Already restarted elevated, still not an administrator (standard account without UAC).
    if ($env:OW_ELEVATED) { Wait-Exit 'Administrator rights are required. Run the script from an administrator account.' }
    try {
        # Through cmd.exe rather than the "runas" verb of .cmd files: that verb runs cmd /C "%1",
        # which drops the quotes of a path holding & ( ) @ ^, such as "InstallationWindows-main (1)".
        $arguments = '/d /c ""{0}" /elevated"' -f $SelfPath
        Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        Wait-Exit 'Administrator rights are required. Run the script again and accept the prompt.'
    }
    exit 0
}

$Host.UI.RawUI.WindowTitle = 'Windows Optimization'
# Progress bars (Appx, DISM, downloads) slow PowerShell 5.1 down and break the step display.
$ProgressPreference = 'SilentlyContinue'

# QuickEdit: a click in the window starts a selection that freezes all output until Enter is pressed.
# Turn it off for this window only (the user's console defaults are not touched).
try {
    Add-Type -Namespace OwNative -Name Console -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
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
    if ($Stop -and $svc.Status -ne 'Stopped') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
    try {
        Set-Service -Name $Name -StartupType $Startup -ErrorAction Stop
    } catch {
        # Some services refuse Set-Service: fall back to the registry Start value.
        $startValue = @{ 'Automatic' = 2; 'Manual' = 3; 'Disabled' = 4 }[$Startup]
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name 'Start' -Value $startValue
    }
    if ($Start) { Start-Service -Name $Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
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

# Removes Appx packages for all users and deprovisions them. Fails only if one is still
# installed for the current user; packages Windows marks as non-removable are reported, not failed.
function Uninstall-StoreApp([string[]]$Names) {
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    $protected = @()
    $errors = @{}
    foreach ($name in $Names) {
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
    $remaining = @($Names | Where-Object { $protected -notcontains $_ -and (Get-AppxPackage -Name $_ -ErrorAction SilentlyContinue) })
    if ($remaining.Count -gt 0) {
        throw ('still installed: ' + (($remaining | ForEach-Object { if ($errors[$_]) { '{0} ({1})' -f $_, $errors[$_] } else { $_ } }) -join '; '))
    }
    if ($protected.Count -gt 0) { return (Skip ('protected by Windows, kept: {0}' -f (($protected | Select-Object -Unique) -join ', '))) }
}

# Optional features: one DISM query for the whole run (DISM is slow), updated after each change.
$script:FeatureStates = $null
function Get-FeatureStates {
    if ($null -eq $script:FeatureStates) {
        $script:FeatureStates = @{}
        foreach ($f in @(Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue)) { $script:FeatureStates[$f.FeatureName] = [string]$f.State }
    }
    return $script:FeatureStates
}

function Test-FeatureEnabled([string[]]$Names) {
    $states = Get-FeatureStates
    return [bool]($Names | Where-Object { $states[$_] -like 'Enable*' })
}

# Features missing from this edition (Hyper-V and Sandbox on Home) are ignored.
function Set-Features([string[]]$Names, [bool]$Enabled) {
    $states = Get-FeatureStates
    $failed = @()
    foreach ($name in $Names) {
        if (-not $states.ContainsKey($name)) { continue }
        $on = $states[$name] -like 'Enable*'
        try {
            if ($Enabled -and -not $on) {
                Enable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart | Out-Null
                $states[$name] = 'EnablePending'
            } elseif (-not $Enabled -and $on) {
                Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart | Out-Null
                $states[$name] = 'DisablePending'
            }
        } catch { $failed += $name }
    }
    if ($failed.Count -gt 0) { throw ('not changed: ' + ($failed -join ', ')) }
}

# Windows features cannot be changed reliably while an update waits for a restart.
function Test-RebootPending {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    return [bool]($keys | Where-Object { Test-Path -LiteralPath $_ })
}

# Keeps a copy of the script in ProgramData, so the Desktop shortcut works without the USB key.
# Running a newer setup.cmd from anywhere refreshes the copy; an older one (old USB key) leaves it alone.
function Update-InstalledCopy {
    if ([string]::Equals($SelfPath, $InstalledCopy, [StringComparison]::OrdinalIgnoreCase)) { return }
    if ((Test-Path -LiteralPath $InstalledCopy) -and
        (Get-Item -LiteralPath $InstalledCopy).LastWriteTimeUtc -gt (Get-Item -LiteralPath $SelfPath).LastWriteTimeUtc) { return }
    Copy-Item -LiteralPath $SelfPath -Destination $InstalledCopy -Force
}

function New-DesktopShortcut {
    $powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName))
    $link.TargetPath = $InstalledCopy
    # An existing shortcut keeps its old arguments (powershell.exe -File ...setup.ps1) unless cleared.
    $link.Arguments = ''
    $link.WorkingDirectory = $DataDir
    $link.IconLocation = "$powershell,0"
    $link.Description = 'Windows optimization'
    $link.Save()
}

# Asks the Microsoft Store to update its apps (App Installer / winget included). Runs in the
# background: the Store downloads the updates on its own, nothing to wait for.
function Start-StoreUpdates {
    $apps = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction SilentlyContinue
    if (-not $apps) { return (Skip 'Store update service not available') }
    $apps | Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null
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
# Items: hashtables with Label and optional Hint.
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
            $selected = ($i -eq $index)
            $prefix = if ($selected) { '  > ' } else { '    ' }
            $color = if ($selected) { 'Cyan' } else { 'Gray' }
            Write-Host ($prefix + $item.Label) -ForegroundColor $color
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
# Hardware and system detection
# ---------------------------------------------------------------------------

function Get-GpuVendor([string]$PnpId) {
    if ($PnpId -match 'VEN_10DE') { return 'NVIDIA' }
    if ($PnpId -match 'VEN_1002') { return 'AMD' }
    if ($PnpId -match 'VEN_8086') { return 'Intel' }
    return 'Other'
}

function Test-DiscreteGpuName([string]$Name) {
    return ($Name -match 'GeForce|RTX|GTX|Quadro|Radeon RX|Radeon (AI )?Pro|Radeon VII')
}

function Get-SystemInfo {
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $cs  = Get-CimInstance -ClassName Win32_ComputerSystem
    # Mobile system type, or a portable chassis (laptop, notebook, 2-in-1, tablet).
    # Win32_Battery is not used: a USB UPS shows up as a battery.
    $chassis = @((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    $isLaptop = ($cs.PCSystemType -eq 2) -or [bool]($chassis | Where-Object { $_ -in 8, 9, 10, 14, 30, 31, 32 })
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
        CpuName      = $cpu.Name.Trim()
        CpuVendor    = $cpuVendor
        # Every X3D with more than 8 cores has two CCDs (7900X3D to 9950X3D, 7945HX3D, 9955HX3D).
        IsDualCcdX3D = ($cpu.Name -match 'X3D' -and $cpu.NumberOfCores -gt 8)
        Gpus         = $gpus
        IsLaptop     = $isLaptop
        IsVM         = $isVm
        RamGB        = $ramGB
        HasLinux     = $hasLinux
        Edition      = $os.Caption
        Build        = [Environment]::OSVersion.Version.Build
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

# The hypervisor also runs for VBS / memory integrity: "enabled" when it runs or when a feature is on.
function Get-VirtualizationEnabled {
    if ((Get-CimInstance -ClassName Win32_ComputerSystem).HypervisorPresent) { return $true }
    return (Test-FeatureEnabled $VirtualizationDisable)
}

function Get-OneDriveInstalled {
    return (Test-Path -LiteralPath "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or
           (Test-Path -LiteralPath "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")
}

function Test-SteamInstalled {
    $exe = Get-RegValue 'HKCU:\Software\Valve\Steam' 'SteamExe'
    return ($exe -and (Test-Path -LiteralPath $exe)) -or (Test-Path -LiteralPath "${env:ProgramFiles(x86)}\Steam\steam.exe")
}

function Test-DiscordInstalled {
    return (Test-Path -LiteralPath "$env:LOCALAPPDATA\Discord\Update.exe")
}

function Get-ReturningApps {
    $installed = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    return @($ReturningApps.Keys | Where-Object { $installed -contains $_ })
}

# ---------------------------------------------------------------------------
# winget
# ---------------------------------------------------------------------------

function Initialize-Winget {
    if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue) { return $true }
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction SilentlyContinue
    return [bool](Get-Command -Name 'winget' -ErrorAction SilentlyContinue)
}

# One winget call per package: "install" already detects an installed package.
$WingetAlreadyInstalled = -1978335135  # 0x8A150061 (with --no-upgrade)
$WingetNoUpdate         = -1978335189  # 0x8A15002B
$WingetNotFound         = -1978335212  # 0x8A150014

function Install-WingetPackage([string]$Id, [string]$Source = 'winget') {
    $arguments = @('install', '--id', $Id, '--exact', '--source', $Source, '--silent', '--no-upgrade',
                   '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    Invoke-Native -File 'winget' -Arguments $arguments -OkCodes @(0, $WingetAlreadyInstalled, $WingetNoUpdate) | Out-Null
    if ($LASTEXITCODE -ne 0) { return (Skip 'already installed') }
}

function Uninstall-WingetPackage([string]$Id) {
    Invoke-Native -File 'winget' -Arguments @('uninstall', '--id', $Id, '--exact', '--silent', '--accept-source-agreements', '--disable-interactivity') -OkCodes @(0, $WingetNotFound) | Out-Null
    if ($LASTEXITCODE -ne 0) { return (Skip 'not installed') }
}

# ---------------------------------------------------------------------------
# Applications
# ---------------------------------------------------------------------------

function Set-FirefoxConfig {
    $firefoxDir = Join-Path $env:ProgramFiles 'Mozilla Firefox'
    if (-not (Test-Path -LiteralPath (Join-Path $firefoxDir 'firefox.exe'))) { return (Skip 'Firefox not found') }
    if ((Test-Path -LiteralPath (Join-Path $firefoxDir 'firefox.cfg')) -and
        (Test-Path -LiteralPath (Join-Path $firefoxDir 'distribution\extensions\uBlock0@raymondhill.net.xpi'))) { return (Skip 'already done') }
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    # Preferences through AutoConfig instead of enterprise policies: no "managed by your
    # organization" banner, and these are only defaults the user can still change.
    $prefDir = Join-Path $firefoxDir 'defaults\pref'
    New-Item -Path $prefDir -ItemType Directory -Force | Out-Null
    $autoconfig = 'pref("general.config.filename", "firefox.cfg");' + "`n" + 'pref("general.config.obscure_value", 0);' + "`n"
    [IO.File]::WriteAllText((Join-Path $prefDir 'autoconfig.js'), $autoconfig, $utf8)
    $cfg = @'
// Defaults set by setup.cmd (this first line is ignored by Firefox)
defaultPref("datareporting.policy.dataSubmissionEnabled", false);
defaultPref("datareporting.healthreport.uploadEnabled", false);
defaultPref("app.shield.optoutstudies.enabled", false);
defaultPref("browser.newtabpage.activity-stream.feeds.topsites", false);
defaultPref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
// Session: reopen the previous tabs
defaultPref("browser.startup.page", 3);
// AI features
defaultPref("browser.ml.chat.enabled", false);
defaultPref("browser.ml.chat.shortcuts", false);
defaultPref("browser.ml.linkPreview.enabled", false);
defaultPref("browser.tabs.groups.smart.enabled", false);
// Sponsored content
defaultPref("browser.newtabpage.activity-stream.showSponsored", false);
defaultPref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
defaultPref("browser.urlbar.suggest.quicksuggest.sponsored", false);
// Extension and feature recommendations, Firefox View
defaultPref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
defaultPref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
defaultPref("extensions.htmlaboutaddons.recommendations.enabled", false);
defaultPref("extensions.getAddons.showPane", false);
defaultPref("browser.discovery.enabled", false);
defaultPref("browser.tabs.firefox-view", false);
// Privacy
defaultPref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
defaultPref("app.normandy.enabled", false);
defaultPref("datareporting.usage.uploadEnabled", false);
defaultPref("dom.private-attribution.submission.enabled", false);
defaultPref("privacy.globalprivacycontrol.enabled", true);
'@
    [IO.File]::WriteAllText((Join-Path $firefoxDir 'firefox.cfg'), $cfg, $utf8)

    # uBlock Origin: Firefox installs the extensions of distribution\extensions in every new profile.
    $extDir = Join-Path $firefoxDir 'distribution\extensions'
    $xpi = Join-Path $extDir 'uBlock0@raymondhill.net.xpi'
    if (-not (Test-Path -LiteralPath $xpi)) {
        New-Item -Path $extDir -ItemType Directory -Force | Out-Null
        # Download elsewhere, then move: an interrupted download must not pass the "already done" check.
        $download = Join-Path $env:TEMP 'uBlock0@raymondhill.net.xpi'
        Invoke-WebRequest -Uri 'https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi' -OutFile $download -UseBasicParsing
        Move-Item -LiteralPath $download -Destination $xpi -Force
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
    # Windows restarts Explorer by itself; start it if it has not after a few seconds.
    $deadline = (Get-Date).AddSeconds(6)
    while ((Get-Date) -lt $deadline -and -not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 300 }
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) { Start-Process 'explorer.exe' }
    # Wait for the taskbar window, then give Explorer time to read the layout before unlocking it.
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        $taskbar = [IntPtr]::Zero
        try { $taskbar = [OwNative.Console]::FindWindow('Shell_TrayWnd', $null) } catch { $null = $_ }
        if ($taskbar -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 3
    Set-RegValue $key 'LockedStartLayout' 0
}

function Disable-StartupEntry([string]$Name) {
    # Same flag Task Manager writes when an entry is disabled (03 + timestamp).
    $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTimeUtc()))
    Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' $Name $bytes 'Binary'
}

function Invoke-AppSteps($Selected) {
    Write-Section 'Applications'

    if (-not (Initialize-Winget)) {
        Invoke-Step 'winget' { throw 'winget not found: update "App Installer" from the Microsoft Store, then run the script again.' }
        return
    }

    Invoke-Step 'winget sources' {
        # On a fresh install the sources are often out of date and installs fail until refreshed.
        try { Invoke-Native -File 'winget' -Arguments @('source', 'update', '--disable-interactivity') | Out-Null }
        catch {
            Invoke-Native -File 'winget' -Arguments @('source', 'reset', '--force', '--disable-interactivity') | Out-Null
            Invoke-Native -File 'winget' -Arguments @('source', 'update', '--disable-interactivity') | Out-Null
        }
    }
    $script:FirefoxInstalledNow = $false
    Invoke-Step 'Firefox' {
        $result = Install-WingetPackage 'Mozilla.Firefox.fr'
        if (-not $result) { $script:FirefoxInstalledNow = $true }
        $result
    }
    Invoke-Step 'Firefox: uBlock Origin and settings' { Set-FirefoxConfig }
    # Only right after the install: the user may have changed the pins since.
    if ($script:FirefoxInstalledNow) { Invoke-Step 'Firefox: pin to the taskbar' { Add-FirefoxToTaskbar } }
    Invoke-Step 'VLC' {
        $result = Install-WingetPackage 'VideoLAN.VLC'
        Remove-Shortcut @('VLC media player.lnk')
        $result
    }
    Invoke-Step '7-Zip' { Install-WingetPackage '7zip.7zip' }

    if ($Selected.Steam) {
        Invoke-Step 'Steam' { Install-WingetPackage 'Valve.Steam' }
        Invoke-Step 'Steam: no launch at startup' { Disable-StartupEntry 'Steam' }
    }
    if ($Selected.Discord) {
        Invoke-Step 'Discord' { Install-WingetPackage 'Discord.Discord' }
        Invoke-Step 'Discord: no launch at startup' { Disable-StartupEntry 'Discord' }
    }
}

# ---------------------------------------------------------------------------
# Optimizations (no rollback)
# ---------------------------------------------------------------------------

function Invoke-PrivacySteps {
    Write-Section 'Privacy and telemetry'

    Invoke-Step 'Telemetry and useless services' {
        $failed = @()
        foreach ($name in $ServicesToDisable) {
            try { [void](Set-ServiceStartup -Name $name -Startup Disabled -Stop) } catch { $failed += $name }
        }
        if ($failed.Count -gt 0) { throw ('not changed: ' + ($failed -join ', ')) }
    }

    Invoke-Step 'Telemetry scheduled tasks' {
        $failed = @()
        foreach ($task in $TelemetryTasks) {
            try { Disable-TaskByPath $task } catch { $failed += (Split-Path -Path $task -Leaf) }
        }
        if ($failed.Count -gt 0) { throw ('not changed: ' + ($failed -join ', ')) }
    }

    Invoke-Step 'Windows Error Reporting' {
        Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    }

    Invoke-Step 'Advertising ID and tailored experiences' {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
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
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsWebSuggestionsEnabled' 0
    }
}

function Invoke-AiSteps {
    Write-Section 'AI'

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

function Invoke-SystemSteps($Info) {
    Write-Section 'System and services'

    Invoke-Step 'Hibernation' {
        if ($Info.IsLaptop) { return (Skip 'laptop, Windows uses it to protect the battery in standby') }
        Invoke-Native -File 'powercfg.exe' -Arguments @('/hibernate', 'off') | Out-Null
    }

    Invoke-Step 'Background apps' {
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
        # Xbox app and Game Bar keep working in the background when they are installed.
        $allowed = @('Microsoft.SecHealthUI_8wekyb3d8bbwe')
        foreach ($name in 'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay') {
            if (Get-AppxPackage -Name $name -ErrorAction SilentlyContinue) { $allowed += "${name}_8wekyb3d8bbwe" }
        }
        Set-RegValue $key 'LetAppsRunInBackground' 2
        Set-RegValue $key 'LetAppsRunInBackground_ForceAllowTheseApps' ([string[]]$allowed) 'MultiString'
    }

    Invoke-Step 'Peer-to-peer update sharing' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    }

    Invoke-Step 'Remote Assistance' {
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
    }

    Invoke-Step 'Mobile devices (Cross Device Experience Host)' {
        # Background process at every logon; Phone Link is already removed by the USB key.
        Uninstall-StoreApp @('MicrosoftWindows.CrossDevice')
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

    if ($Info.IsDualCcdX3D) {
        # The AMD driver parks the CCD without 3D V-Cache during games: keep the plain Balanced
        # plan, without the "Best performance" mode whose effect on core parking is not documented.
        Invoke-Step 'Balanced plan (dual-CCD X3D: core parking kept)' {
            Invoke-Native -File 'powercfg.exe' -Arguments @('/setactive', $SchemeBalanced) | Out-Null
        }
    } else {
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
    }

    Invoke-Step 'PCI Express link state power management' {
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
        $failed = @()
        foreach ($adapter in $adapters) {
            if ($adapter.NdisPhysicalMedium -eq 14) {
                foreach ($keyword in $keywords) {
                    $prop = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -ErrorAction SilentlyContinue
                    if ($prop -and "$($prop.RegistryValue)" -ne '0') {
                        try { Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -RegistryValue '0' -NoRestart }
                        catch { $failed += ('{0} ({1})' -f $keyword, $adapter.Name) }
                    }
                }
            }
        }
        if ($failed.Count -gt 0) { throw ('not changed: ' + ($failed -join ', ')) }
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
        $failed = @()
        foreach ($ext in $PropertiesOnlyExtensions) {
            try {
                $key = "HKLM:\SOFTWARE\Classes\$ext\PersistentHandler"
                $current = Get-RegValue $key '(default)'
                if ($current -eq $NullPersistentHandler) { continue }
                if ($current) { Set-RegValue $key 'OriginalPersistentHandler' $current 'String' }
                Set-RegValue $key '(default)' $NullPersistentHandler 'String'
            } catch { $failed += $ext }
        }
        if ($failed.Count -gt 0) { throw ('not changed: ' + ($failed -join ', ')) }
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

function Get-NotificationsEnabled {
    return ((Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled') -ne 0)
}

function Set-Notifications([bool]$Enabled) {
    $label = if ($Enabled) { 'Notifications on' } else { 'Notifications off' }
    Invoke-Step $label {
        # Same switch as Settings > System > Notifications.
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' ([int]$Enabled)
    }
}

function Invoke-NotificationSteps {
    Write-Section 'Notifications'
    Invoke-Step 'Lock screen notifications, tips and welcome screens' {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
    }
}

# ---------------------------------------------------------------------------
# Changes checked in the list
# ---------------------------------------------------------------------------

function Disable-Xbox([bool]$KeepGameBar = $false) {
    Invoke-Step 'Remove Xbox apps' {
        $targets = @($XboxPackages | Where-Object { -not ($KeepGameBar -and $_ -eq 'Microsoft.XboxGamingOverlay') })
        Uninstall-StoreApp $targets
    }
    if (-not $KeepGameBar) {
        Invoke-Step 'Xbox controller button: no Game Bar' {
            Set-RegValue 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0
        }
    }
}

function Enable-Xbox {
    if (-not (Initialize-Winget)) { Invoke-Step 'winget' { throw 'winget not found.' }; return }
    foreach ($entry in $XboxStoreIds.GetEnumerator()) {
        $id = $entry.Value
        Invoke-Step ('Install {0}' -f $entry.Key) { Install-WingetPackage -Id $id -Source 'msstore' }
    }
    Invoke-Step 'Xbox controller button: Game Bar' {
        Set-RegValue 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 1
    }
}

function Disable-Printing {
    Invoke-Step 'Print Spooler' { [void](Set-ServiceStartup -Name 'Spooler' -Startup Disabled -Stop) }
    Invoke-Step 'PDF and XPS virtual printers' { Set-Features $PrintingFeatures $false }
}

function Enable-Printing {
    Invoke-Step 'Print Spooler' { [void](Set-ServiceStartup -Name 'Spooler' -Startup Automatic -Start) }
    Invoke-Step 'PDF and XPS virtual printers' { Set-Features $PrintingFeatures $true }
}

function Disable-Virtualization {
    Invoke-Step 'WSL, virtualization platforms, Hyper-V and Sandbox' { Set-Features $VirtualizationDisable $false }
    Invoke-Step 'Hypervisor at boot' {
        Invoke-Native -File 'bcdedit.exe' -Arguments @('/set', 'hypervisorlaunchtype', 'off') | Out-Null
    }
}

function Enable-Virtualization {
    # Hyper-V and Sandbox (Pro editions) are not turned back on: Windows features, if needed.
    Invoke-Step 'WSL and virtualization platforms' { Set-Features $VirtualizationEnable $true }
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

function Remove-ReturningApps {
    Invoke-Step 'Remove apps installed again' { Uninstall-StoreApp @(Get-ReturningApps) }
}

# The list shows, for each item, the action that changes its current state. Nothing is checked:
# an unchecked item is left as it is.
function Get-ChangeItems {
    $items = New-Object System.Collections.Generic.List[object]
    $add = { param($Id, $Label, $Hint) $items.Add(@{ Id = $Id; Label = $Label; Hint = $Hint; Value = $false }) }

    if (Get-XboxEnabled) { & $add 'XboxOff' 'Remove Xbox (Xbox app, Game Pass, Game Bar)' 'Controllers keep working. Can be installed again from this list.' }
    else { & $add 'XboxOn' 'Install Xbox (Xbox app, Game Bar)' 'Needed for Game Pass and the Game Bar.' }

    if (Get-PrintingEnabled) { & $add 'PrintingOff' 'Disable printing' 'Print spooler and PDF/XPS virtual printers.' }
    else { & $add 'PrintingOn' 'Enable printing' 'Print spooler and PDF/XPS virtual printers.' }

    if (Get-VirtualizationEnabled) { & $add 'VirtOff' 'Disable WSL / virtualization' 'Docker Desktop, WSL2 and Android emulators stop working.' }
    else { & $add 'VirtOn' 'Enable WSL / virtualization' 'Needed for Docker Desktop, WSL2 and Android emulators.' }

    if (Get-OneDriveInstalled) { & $add 'OneDriveOff' 'Uninstall OneDrive' 'Microsoft file sync.' }
    else { & $add 'OneDriveOn' 'Install OneDrive' 'Microsoft file sync.' }

    if (Get-NotificationsEnabled) { & $add 'NotificationsOff' 'Turn off notifications' 'No notifications at all: Discord, Steam, Windows Update, Windows Security.' }
    else { & $add 'NotificationsOn' 'Turn on notifications' 'Discord, Steam, Windows Update, Windows Security.' }

    $returning = @(Get-ReturningApps)
    if ($returning.Count -gt 0) {
        $names = ($returning | ForEach-Object { $ReturningApps[$_] }) -join ', '
        & $add 'ReturningApps' "Remove apps installed again ($names)" 'Removed by the USB key, installed again since by Windows Update or the Store.'
    }

    if (-not (Test-SteamInstalled)) { & $add 'Steam' 'Install Steam' 'Installed with winget, not launched at startup.' }
    if (-not (Test-DiscordInstalled)) { & $add 'Discord' 'Install Discord' 'Installed with winget, not launched at startup.' }
    return $items.ToArray()
}

function Invoke-ChangeSteps($Selected, [bool]$KeepGameBar) {
    $changes = @($Selected.Keys | Where-Object { $_ -notin 'Steam', 'Discord' })
    if ($changes.Count -eq 0) { return }
    Write-Section 'Changes'
    if ($Selected.XboxOff) { Disable-Xbox -KeepGameBar $KeepGameBar }
    if ($Selected.XboxOn) { Enable-Xbox }
    if ($Selected.PrintingOff) { Disable-Printing }
    if ($Selected.PrintingOn) { Enable-Printing }
    if ($Selected.VirtOff) { Disable-Virtualization }
    if ($Selected.VirtOn) { Enable-Virtualization }
    if ($Selected.OneDriveOff) { Disable-OneDrive }
    if ($Selected.OneDriveOn) { Enable-OneDrive }
    if ($Selected.NotificationsOff) { Set-Notifications $false }
    if ($Selected.NotificationsOn) { Set-Notifications $true }
    if ($Selected.ReturningApps) { Remove-ReturningApps }
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
        Write-Check 'info' 'Virtual machine: hardware checks skipped'
        return
    }

    # Secure Boot: required by anti-cheats (Vanguard: error VAN 9003). The 2011 certificate that
    # signs the Windows boot manager expires in October 2026; Windows Update installs the 2023 ones.
    try {
        if (Confirm-SecureBootUEFI) {
            $db = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name db).Bytes)
            if ($db -match 'Windows UEFI CA 2023') { Write-Check 'ok' 'Secure Boot enabled, 2023 certificates present' }
            else { Write-Check 'warn' 'Secure Boot enabled, 2023 certificates missing' 'Install all Windows updates, then update the BIOS' }
        } else {
            Write-Check 'warn' 'Secure Boot disabled' 'Required by the anti-cheat of Valorant, League of Legends, Battlefield...'
        }
    } catch {
        Write-Check 'info' 'Secure Boot not supported (legacy BIOS / CSM)'
    }

    if (-not $Info.IsLaptop) {
        # RAM speed: without its EXPO / XMP profile a kit runs at the base JEDEC speed, and a BIOS
        # update or a CMOS reset silently goes back to it. The rated speed is printed on the kit.
        $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory)
        if ($modules.Count -gt 0) {
            $speed = [int]($modules | Measure-Object -Property ConfiguredClockSpeed -Maximum).Maximum
            $parts = @($modules | ForEach-Object { ([string]$_.PartNumber).Trim() } | Where-Object { $_ } | Select-Object -Unique)
            $label = 'RAM at {0} MT/s' -f $speed
            if ($parts.Count -gt 0) { $label += ' (kit: {0})' -f ($parts -join ', ') }
            # Speed is the module's JEDEC (base) speed: running above it means EXPO / XMP is active.
            $jedec = [int]($modules | Measure-Object -Property Speed -Minimum).Minimum
            if ($jedec -gt 0 -and $speed -gt $jedec) {
                Write-Check 'ok' ($label + ', EXPO/XMP active')
            } else {
                Write-Check 'info' ($label + ', no EXPO/XMP profile detected') 'If the kit is rated faster, enable EXPO (AMD) or XMP (Intel) in the BIOS'
            }
        }

        # Integrated graphics next to a graphics card: it reserves part of the RAM for itself.
        $integrated = @($Info.Gpus | Where-Object { -not $_.IsDiscrete -and -not $_.IsBasic -and ($_.Vendor -eq 'AMD' -or $_.Vendor -eq 'Intel') })
        if ($integrated.Count -gt 0 -and @($Info.Gpus | Where-Object { $_.IsDiscrete }).Count -gt 0) {
            $installed = ($modules | Measure-Object -Property Capacity -Sum).Sum
            $visible = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
            $reserved = [math]::Max(0, [math]::Round(($installed - $visible) / 1GB, 1))
            Write-Check 'info' ('Integrated graphics enabled ({0}), {1} GB of RAM reserved' -f $integrated[0].Name, $reserved) 'Not used for video encoding or an extra display? Disable it in the BIOS'
        }
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

    $Info.IsLaptop = ((Read-Menu -Header 'Type of PC?' -Items @(@{ Label = 'Desktop' }, @{ Label = 'Laptop' }) -Default ([int]$Info.IsLaptop)) -eq 1)
    if ($Info.CpuVendor -eq 'AMD') {
        $Info.IsDualCcdX3D = Read-YesNo 'Is it an X3D with more than 8 cores (7900X3D, 9950X3D, 9955HX3D...)?' $Info.IsDualCcdX3D
    }
    return $Info
}

# Same run every time: applications installed if missing, all optimizations applied again,
# and only the changes checked in the list.
function Start-Run($Info) {
    if (Test-RebootPending) { Wait-Exit 'A restart is pending (Windows Update). Restart the PC, then run the script again.' }
    $Info = Confirm-Hardware $Info

    Write-Title
    Write-Host '  Reading the current state...' -ForegroundColor DarkGray
    $items = Read-Checkboxes -Header @('Check what you want to change', 'Nothing checked: optimizations only.') -Items (Get-ChangeItems)
    $selected = @{}
    foreach ($item in $items) { if ($item.Value) { $selected[$item.Id] = $true } }

    $keepGameBar = $false
    if ($selected.XboxOff -and $Info.IsDualCcdX3D) {
        $keepGameBar = Read-YesNo @(
            ('Your {0} uses the Game Bar to send games to the right CCD.' -f $Info.CpuName),
            'Keep the Game Bar?'
        ) $true
    }

    Write-Title
    Write-Section 'Script'
    Invoke-Step 'Desktop shortcut "Optimisation Windows"' {
        Update-InstalledCopy
        New-DesktopShortcut
        # Left by earlier versions of the script.
        foreach ($old in 'state.json', 'setup.ps1') { Remove-Item -LiteralPath (Join-Path $DataDir $old) -Force -ErrorAction SilentlyContinue }
    }
    Invoke-AppSteps $selected
    Invoke-ChangeSteps $selected $keepGameBar
    Invoke-PrivacySteps
    Invoke-AiSteps
    Invoke-SystemSteps $Info
    Invoke-PowerSteps $Info
    Invoke-GamingSteps
    Invoke-SearchSteps
    Invoke-EdgeSteps
    Invoke-InterfaceSteps
    Invoke-NotificationSteps

    # Last, so the Store does not update App Installer while winget is installing apps.
    Write-Section 'Microsoft Store'
    Invoke-Step 'Store app updates (in the background)' { Start-StoreUpdates }

    Show-HealthCheck $Info
    Write-Summary
    Wait-Exit 'Restart the PC to apply all settings.'
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

Write-Title
Write-Host '  Detecting hardware...' -ForegroundColor DarkGray
$systemInfo = Get-SystemInfo

Start-Run $systemInfo
