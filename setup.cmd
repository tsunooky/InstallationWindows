<# : batch portion
@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "OW_SELF=%~f0"
set "OW_ELEVATED="
if /i "%~1"=="/elevated" set "OW_ELEVATED=1"
set "OW_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "OW_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%OW_PS%" -NoProfile -Command ". ([scriptblock]::Create((Get-Content -LiteralPath $env:OW_SELF -Raw)))"
if errorlevel 1 pause
exit /b
#>

$MinBuild      = 26100
$TaskbarXml    = Join-Path $env:SystemRoot 'Setup\Scripts\TaskbarLayoutModification.xml'
$AppPrivacyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
$AppIds        = @('Firefox', 'Vlc', 'Steam', 'Discord')

$SchemeBalanced        = '381b4222-f694-41f0-9685-ff5bb260df2e'
$OverlayBestPerf       = 'ded574b5-45a0-4f42-8737-46345c09c238'
$NullPersistentHandler = '{098f2470-bae0-11cd-b579-08002b30bfeb}'

$ServicesToDisable = @(
    'DiagTrack',
    'WSAIFabricSvc',
    'TrkWks',
    'LanmanServer'
)

$XboxPackages = @(
    'Microsoft.GamingApp',
    'Microsoft.GamingServices',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxGameOverlay',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.Edge.GameAssist'
)

$XboxStoreIds = [ordered]@{
    'Xbox'          = '9MV0B5HZVK9Z'
    'Xbox Game Bar' = '9NZKPSTSNW4P'
}

$ReturningApps = [ordered]@{
    'Microsoft.OutlookForWindows'  = 'Outlook'
    'Microsoft.Copilot'            = 'Copilot'
    'Microsoft.MicrosoftOfficeHub' = 'Microsoft 365'
    'MSTeams'                      = 'Teams'
    'Microsoft.Windows.DevHome'    = 'Dev Home'
}

$PrintingFeatures      = @('Printing-PrintToPDFServices-Features', 'Printing-XPSServices-Features')
$VirtualizationEnable  = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform', 'HypervisorPlatform')
$VirtualizationDisable = $VirtualizationEnable + @('Microsoft-Hyper-V-All', 'Containers-DisposableClientVM')

$PropertiesOnlyExtensions = @(
    '.txt', '.log', '.md', '.csv', '.json', '.xml', '.ini', '.cfg', '.yml', '.yaml', '.toml',
    '.ps1', '.psm1', '.bat', '.cmd', '.sh', '.py', '.js', '.mjs', '.ts', '.tsx', '.jsx',
    '.java', '.c', '.cpp', '.h', '.hpp', '.cs', '.go', '.rs', '.php', '.rb', '.lua', '.sql',
    '.html', '.htm', '.css', '.scss', '.vue',
    '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.pdf', '.rtf', '.odt', '.ods', '.odp'
)

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

$SelfPath = $env:OW_SELF
if (-not $SelfPath -or -not (Test-Path -LiteralPath $SelfPath)) {
    Wait-Exit 'Run setup.cmd with a double-click.'
}

if (-not (Test-Admin)) {
    if ($env:OW_ELEVATED) { Wait-Exit 'Administrator rights are required. Run the script from an administrator account.' }
    try {
        $arguments = '/d /c ""{0}" /elevated"' -f $SelfPath
        Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        Wait-Exit 'Administrator rights are required. Run the script again and accept the prompt.'
    }
    exit 0
}

$Host.UI.RawUI.WindowTitle = 'Windows Optimization'
$ProgressPreference = 'SilentlyContinue'

$script:SpinnerReady = $false
try {
    Add-Type -Namespace OwNative -Name Console -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool WriteConsoleOutputCharacter(IntPtr hConsoleOutput, string lpCharacter, uint nLength, uint dwWriteCoord, out uint lpNumberOfCharsWritten);

static readonly object spinGate = new object();
static System.Threading.Timer spinTimer;
static string[] spinFrames;
static int spinX, spinY, spinIndex, clockRight, clockY;
static DateTime clockStart;

static void Put(string text, int x, int y) {
    uint written;
    WriteConsoleOutputCharacter(GetStdHandle(-11), text, (uint)text.Length, (uint)((y << 16) | x), out written);
}

static void SpinTick(object state) {
    lock (spinGate) {
        if (spinTimer == null) return;
        try {
            spinIndex = (spinIndex + 1) % spinFrames.Length;
            Put(spinFrames[spinIndex], spinX, spinY);
            TimeSpan t = DateTime.Now - clockStart;
            string clock = string.Format("{0}:{1:00}", (int)t.TotalMinutes, t.Seconds);
            Put(clock, clockRight - clock.Length, clockY);
        } catch { }
    }
}

public static void StartSpinner(string[] frames, int x, int y, int right, int top, DateTime start) {
    lock (spinGate) {
        spinFrames = frames; spinX = x; spinY = y; spinIndex = 0;
        clockRight = right; clockY = top; clockStart = start;
        spinTimer = new System.Threading.Timer(SpinTick, null, 150, 150);
    }
}

public static void StopSpinner() {
    lock (spinGate) {
        if (spinTimer != null) { spinTimer.Dispose(); spinTimer = null; }
    }
}
'@
    $script:SpinnerReady = $true
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

function Uninstall-StoreApp([string[]]$Names) {
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    $protected = @()
    $errors = @{}
    foreach ($name in $Names) {
        foreach ($package in @($provisioned | Where-Object { $_.DisplayName -eq $name })) {
            Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $package.PackageName -ErrorAction SilentlyContinue | Out-Null
        }
        foreach ($package in @(Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue)) {
            if ($package.NonRemovable) { $protected += $name; continue }
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

function Set-Features([string[]]$Names, [bool]$Enabled) {
    $states = Get-FeatureStates
    Invoke-ForEachItem $Names {
        param($Feature)
        if (-not $states.ContainsKey($Feature)) { return }
        $on = $states[$Feature] -like 'Enable*'
        if ($Enabled -and -not $on) {
            Enable-WindowsOptionalFeature -Online -FeatureName $Feature -NoRestart
            $states[$Feature] = 'EnablePending'
        } elseif (-not $Enabled -and $on) {
            Disable-WindowsOptionalFeature -Online -FeatureName $Feature -NoRestart
            $states[$Feature] = 'DisablePending'
        }
    }
}

function Test-RebootPending {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    return [bool]($keys | Where-Object { Test-Path -LiteralPath $_ })
}

function Start-StoreUpdates {
    $apps = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction SilentlyContinue
    if (-not $apps) { return (Skip 'Store update service not available') }
    $apps | Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null
}

$FrameWidth = 78
$BoxChar = @{
    TL = [string][char]0x256D; TR = [string][char]0x256E; BL = [string][char]0x2570; BR = [string][char]0x256F
    H = [string][char]0x2500; V = [string][char]0x2502; LT = [string][char]0x251C; RT = [string][char]0x2524
}
$Symbol = @{
    Ok = [string][char]0x2713; Fail = [string][char]0x2717; Todo = [string][char]0x00B7; Arrow = [string][char]0x2192
    Pointer = [string][char]0x25B8; Full = [string][char]0x2588; Light = [string][char]0x2591
}
$Spinner = [string[]]@(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F | ForEach-Object { [string][char]$_ })

function Clear-KeyBuffer {
    while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
}

function Wait-WindowSize {
    while ([Console]::WindowWidth -lt ($FrameWidth + 2) -or [Console]::WindowHeight -lt 25) {
        Clear-Host
        Write-Host ''
        Write-Host ('  Make this window larger (at least {0} x 25), then press a key.' -f ($FrameWidth + 2)) -ForegroundColor Yellow
        Clear-KeyBuffer
        [void][Console]::ReadKey($true)
    }
}

function Format-Elapsed([datetime]$Since) {
    $t = (Get-Date) - $Since
    return ('{0}:{1:00}' -f [int][math]::Floor($t.TotalMinutes), $t.Seconds)
}

function Get-Truncated([string]$Text, [int]$Max, [switch]$Tail) {
    if ($Text.Length -le $Max) { return $Text }
    if ($Tail) { return '...' + $Text.Substring($Text.Length - ($Max - 3)) }
    return $Text.Substring(0, $Max - 3) + '...'
}

function Get-Wrapped([string]$Text, [int]$Width) {
    $lines = New-Object System.Collections.Generic.List[string]
    $line = ''
    foreach ($word in ($Text -split ' ')) {
        if ($line.Length -eq 0) { $line = $word }
        elseif ($line.Length + 1 + $word.Length -le $Width) { $line += ' ' + $word }
        else { $lines.Add($line); $line = $word }
    }
    if ($line.Length -gt 0) { $lines.Add($line) }
    return $lines.ToArray()
}

function Seg([string]$Text, [string]$Fg = 'Gray', [string]$Bg = '') {
    [pscustomobject]@{ Text = $Text; Fg = $Fg; Bg = $Bg }
}

function Write-Segment($Segment, [string]$Text) {
    if ($Text.Length -eq 0) { return }
    if ($Segment.Bg) { Write-Host $Text -ForegroundColor $Segment.Fg -BackgroundColor $Segment.Bg -NoNewline }
    else { Write-Host $Text -ForegroundColor $Segment.Fg -NoNewline }
}

function Write-FrameLine([string]$Left, [string]$Right, [string]$Title = '', [string]$Info = '') {
    $head = ''
    if ($Title) { $head = $BoxChar.H + ' ' + $Title + ' ' }
    $tail = ''
    if ($Info) { $tail = ' ' + $Info + ' ' + $BoxChar.H }
    Write-Host $Left -ForegroundColor DarkGray -NoNewline
    if ($Title) {
        Write-Host ($BoxChar.H + ' ') -ForegroundColor DarkGray -NoNewline
        Write-Host $Title -ForegroundColor White -NoNewline
        Write-Host ' ' -NoNewline
    }
    Write-Host ($BoxChar.H * ($FrameWidth - 2 - $head.Length - $tail.Length)) -ForegroundColor DarkGray -NoNewline
    if ($Info) {
        Write-Host ' ' -NoNewline
        Write-Host $Info -ForegroundColor Gray -NoNewline
        Write-Host (' ' + $BoxChar.H) -ForegroundColor DarkGray -NoNewline
    }
    Write-Host $Right -ForegroundColor DarkGray
}

function Write-FrameRow([object[]]$Left = @(), [object[]]$Right = @()) {
    $rightLength = 0
    foreach ($segment in $Right) { $rightLength += $segment.Text.Length }
    $room = $FrameWidth - 2 - $rightLength
    Write-Host $BoxChar.V -ForegroundColor DarkGray -NoNewline
    $used = 0
    foreach ($segment in $Left) {
        $text = $segment.Text
        if ($used + $text.Length -gt $room) { $text = $text.Substring(0, [math]::Max(0, $room - $used)) }
        Write-Segment $segment $text
        $used += $text.Length
    }
    Write-Host (' ' * ($room - $used)) -NoNewline
    foreach ($segment in $Right) { Write-Segment $segment $segment.Text }
    Write-Host $BoxChar.V -ForegroundColor DarkGray
}

function Write-Button([string]$Indent, [string[]]$Labels, [int]$Focus, [object[]]$After = @()) {
    $top = @(Seg $Indent)
    $middle = @(Seg $Indent)
    $bottom = @(Seg $Indent)
    for ($i = 0; $i -lt $Labels.Count; $i++) {
        $border = 'DarkGray'
        $label = Seg $Labels[$i] 'White'
        if ($i -eq $Focus) { $border = 'Cyan'; $label = Seg $Labels[$i] 'Black' 'Cyan' }
        $line = $BoxChar.H * $Labels[$i].Length
        if ($i -gt 0) { $top += Seg '  '; $middle += Seg '  '; $bottom += Seg '  ' }
        $top += Seg ($BoxChar.TL + $line + $BoxChar.TR) $border
        $middle += @((Seg $BoxChar.V $border), $label, (Seg $BoxChar.V $border))
        $bottom += Seg ($BoxChar.BL + $line + $BoxChar.BR) $border
    }
    Write-FrameRow -Left $top
    Write-FrameRow -Left ($middle + $After)
    Write-FrameRow -Left $bottom
}

function Write-KeyHelp([string[]]$Pairs) {
    $segments = @(Seg ' ')
    for ($i = 0; $i -lt $Pairs.Count; $i += 2) {
        $segments += @((Seg (' ' + $Pairs[$i]) 'Cyan'), (Seg (' ' + $Pairs[$i + 1] + '  ') 'DarkGray'))
    }
    Write-FrameRow -Left $segments
}

function Show-Loading {
    Wait-WindowSize
    try { [Console]::CursorVisible = $false } catch { $null = $_ }
    Clear-Host
    Write-FrameLine $BoxChar.TL $BoxChar.TR 'Windows Optimization'
    Write-FrameRow
    Write-FrameRow -Left (Seg '  Reading the current state...' 'DarkGray')
    Write-FrameRow
    Write-FrameLine $BoxChar.BL $BoxChar.BR
}

function Join-Words([string[]]$Words) {
    if ($Words.Count -le 1) { return ($Words -join '') }
    return (($Words[0..($Words.Count - 2)] -join ', ') + ' and ' + $Words[-1])
}

function Show-SelectionFrame([object[]]$Items, [int]$Focus) {
    [Console]::SetCursorPosition(0, 0)
    Write-FrameLine $BoxChar.TL $BoxChar.TR 'Windows Optimization'
    Write-FrameRow
    Write-FrameRow -Left (Seg '  CHECK WHAT YOU USE' 'White')
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $pointer = '    '
        $color = 'Gray'
        if ($i -eq $Focus) { $pointer = '  ' + $Symbol.Pointer + ' '; $color = 'Cyan' }
        $check = Seg '[ ] ' 'DarkGray'
        if ($Items[$i].Value) { $check = Seg '[x] ' 'Green' }
        Write-FrameRow -Left @((Seg $pointer 'Cyan'), $check, (Seg $Items[$i].Label $color))
    }
    Write-FrameRow

    $changes = @((Get-SelectedChanges $Items).Values)
    if ($Focus -lt $Items.Count) {
        $text = $Items[$Focus].Hint
        $color = 'Yellow'
    } elseif ($changes.Count -eq 0) {
        $text = 'Nothing to change: optimizations only.'
        $color = 'Green'
    } else {
        $words = Join-Words $changes
        $text = 'Will ' + $words + '.'
        $color = 'Yellow'
    }
    $lines = @(Get-Wrapped $text ($FrameWidth - 8))
    for ($i = 0; $i -lt 2; $i++) {
        $line = ''
        if ($i -lt $lines.Count) { $line = $lines[$i] }
        Write-FrameRow -Left (Seg ('    ' + $line) $color)
    }
    Write-FrameRow

    $status = 'No change, optimizations only'
    if ($changes.Count -eq 1) { $status = '1 change + all optimizations' }
    elseif ($changes.Count -gt 1) { $status = '{0} changes + all optimizations' -f $changes.Count }
    $buttonFocus = -1
    if ($Focus -eq $Items.Count) { $buttonFocus = 0 }
    Write-Button '    ' @('   START   ') $buttonFocus @(Seg ('   ' + $status) 'Gray')
    Write-FrameRow
    Write-FrameLine $BoxChar.LT $BoxChar.RT
    Write-KeyHelp @('Up/Down', 'move', 'Space/Enter', 'check', 'Enter on START', 'run', 'Esc', 'quit')
    Write-FrameLine $BoxChar.BL $BoxChar.BR
}

function Read-Selection([object[]]$Items) {
    $focus = 0
    Clear-Host
    Clear-KeyBuffer
    while ($true) {
        Show-SelectionFrame $Items $focus
        $key = [Console]::ReadKey($true).Key
        $count = $Items.Count + 1
        if ($key -eq 'UpArrow') { $focus = ($focus - 1 + $count) % $count }
        elseif ($key -eq 'DownArrow') { $focus = ($focus + 1) % $count }
        elseif ($key -eq 'Tab') { $focus = $Items.Count }
        elseif ($key -eq 'Escape') { return $false }
        elseif ($key -eq 'Spacebar' -or $key -eq 'Enter') {
            if ($focus -lt $Items.Count) { $Items[$focus].Value = -not $Items[$focus].Value }
            elseif ($key -eq 'Enter') { return $true }
        }
    }
}

function Read-FrameYesNo([string]$Question, [string[]]$Lines, [bool]$Default = $true) {
    $yes = $Default
    Clear-Host
    Clear-KeyBuffer
    while ($true) {
        [Console]::SetCursorPosition(0, 0)
        Write-FrameLine $BoxChar.TL $BoxChar.TR 'Windows Optimization'
        Write-FrameRow
        Write-FrameRow -Left (Seg ('  ' + $Question) 'White')
        Write-FrameRow
        foreach ($line in $Lines) { Write-FrameRow -Left (Seg ('  ' + $line) 'Gray') }
        Write-FrameRow
        $buttonFocus = 1
        if ($yes) { $buttonFocus = 0 }
        Write-Button '    ' @('  YES  ', '  NO   ') $buttonFocus
        Write-FrameRow
        Write-FrameLine $BoxChar.LT $BoxChar.RT
        Write-KeyHelp @('Left/Right', 'choose', 'Enter', 'confirm')
        Write-FrameLine $BoxChar.BL $BoxChar.BR
        $key = [Console]::ReadKey($true).Key
        if ($key -eq 'LeftArrow' -or $key -eq 'RightArrow' -or $key -eq 'Tab') { $yes = -not $yes }
        elseif ($key -eq 'Enter') { return $yes }
    }
}

function Show-RunFrame {
    $run = $script:Run
    [Console]::SetCursorPosition(0, 0)
    Write-FrameLine $BoxChar.TL $BoxChar.TR 'Windows Optimization' (Format-Elapsed $run.Started)
    Write-FrameRow
    $total = 0
    foreach ($section in $run.Sections) {
        $sectionTotal = [math]::Max($section.Total, $section.Done)
        $total += $sectionTotal
        $count = '{0}/{1}' -f $section.Done, $sectionTotal
        $right = @()
        if ($section.State -eq 'todo') {
            $mark = Seg $Symbol.Todo 'DarkGray'
            $name = Seg $section.Name 'DarkGray'
        } elseif ($section.State -eq 'run') {
            $mark = Seg $Spinner[0] 'Cyan'
            $name = Seg $section.Name 'White'
            $right = @(Seg $count 'Gray')
        } elseif ($section.Failed -gt 0) {
            $mark = Seg $Symbol.Fail 'Red'
            $name = Seg $section.Name 'Gray'
            $right = @((Seg ('{0} failed   ' -f $section.Failed) 'Red'), (Seg $count 'DarkGray'))
        } else {
            $mark = Seg $Symbol.Ok 'Green'
            $name = Seg $section.Name 'Gray'
            $right = @(Seg $count 'DarkGray')
        }
        Write-FrameRow -Left @((Seg '   '), $mark, (Seg ' '), $name) -Right ($right + @(Seg '   '))
    }
    Write-FrameRow
    $barWidth = 56
    $filled = 0
    if ($total -gt 0) { $filled = [int][math]::Floor($barWidth * [math]::Min($run.Done, $total) / $total) }
    Write-FrameRow -Left @((Seg '   '), (Seg ($Symbol.Full * $filled) 'Cyan'), (Seg ($Symbol.Light * ($barWidth - $filled)) 'DarkGray'), (Seg ('  {0}/{1}' -f $run.Done, $total) 'Gray'))
    Write-FrameRow -Left (Seg ('   ' + $run.Label) 'DarkGray')
    Write-FrameRow
    Write-FrameLine $BoxChar.LT $BoxChar.RT
    if ($script:Failures.Count -eq 0) {
        Write-FrameRow -Left (Seg '   No problem so far.' 'DarkGray')
    } elseif ($script:Failures.Count -eq 1) {
        $failure = $script:Failures[0]
        $message = ($failure.Message -replace '\s+', ' ').Trim()
        $room = $FrameWidth - 2 - 6 - $failure.Label.Length - 2
        Write-FrameRow -Left @((Seg '   '), (Seg $Symbol.Fail 'Red'), (Seg (' ' + $failure.Label + ': ') 'Red'), (Seg (Get-Truncated $message $room -Tail) 'DarkRed'))
    } else {
        $labels = @($script:Failures | ForEach-Object { $_.Label })
        Write-FrameRow -Left @((Seg '   '), (Seg $Symbol.Fail 'Red'), (Seg (' {0} problems: {1}' -f $labels.Count, ($labels -join ', ')) 'Red'))
    }
    Write-FrameLine $BoxChar.BL $BoxChar.BR
}

function Show-FinalFrame([object[]]$Checks) {
    $run = $script:Run
    $inner = $FrameWidth - 2
    $ok = 0
    $skipped = 0
    foreach ($section in $run.Sections) { $ok += $section.Ok; $skipped += $section.Skipped }
    $failed = $script:Failures.Count
    Clear-Host
    Write-FrameLine $BoxChar.TL $BoxChar.TR 'Windows Optimization' ('done in ' + (Format-Elapsed $run.Started))
    Write-FrameRow
    $headline = Seg 'DONE' 'Green'
    if ($failed -eq 1) { $headline = Seg 'DONE, 1 PROBLEM' 'Red' }
    elseif ($failed -gt 1) { $headline = Seg ('DONE, {0} PROBLEMS' -f $failed) 'Red' }
    Write-FrameRow -Left @((Seg '   '), $headline, (Seg ('   {0} steps: {1} OK, {2} skipped, {3} failed' -f $run.Done, $ok, $skipped, $failed) 'DarkGray'))
    Write-FrameRow
    if ($failed -gt 0) {
        foreach ($failure in $script:Failures) {
            Write-FrameRow -Left @((Seg '   '), (Seg $Symbol.Fail 'Red'), (Seg (' ' + $failure.Label) 'Red'))
            $lines = @(Get-Wrapped (($failure.Message -replace '\s+', ' ').Trim()) ($inner - 10))
            if ($lines.Count -gt 2) { $lines = @(('...' + $lines[-2]), $lines[-1]) }
            foreach ($line in $lines) { Write-FrameRow -Left (Seg ('     ' + $line) 'DarkRed') }
        }
        Write-FrameRow -Left (Seg '     Failed steps are tried again at the next run.' 'DarkGray')
        Write-FrameRow
    }
    Write-FrameRow -Left (Seg '   HEALTH CHECK' 'DarkGray')
    foreach ($check in $Checks) {
        if ($check.Level -eq 'ok') { $mark = Seg $Symbol.Ok 'Green' }
        elseif ($check.Level -eq 'warn') { $mark = Seg '!' 'Red' }
        else { $mark = Seg 'i' 'Yellow' }
        $lines = @(Get-Wrapped $check.Message ($inner - 6))
        Write-FrameRow -Left @((Seg '   '), $mark, (Seg (' ' + $lines[0]) 'Gray'))
        for ($i = 1; $i -lt $lines.Count; $i++) { Write-FrameRow -Left (Seg ('     ' + $lines[$i]) 'Gray') }
        if ($check.Advice) {
            $lines = @(Get-Wrapped $check.Advice ($inner - 8))
            Write-FrameRow -Left @((Seg '     '), (Seg $Symbol.Arrow 'DarkGray'), (Seg (' ' + $lines[0]) 'DarkGray'))
            for ($i = 1; $i -lt $lines.Count; $i++) { Write-FrameRow -Left (Seg ('       ' + $lines[$i]) 'DarkGray') }
        }
    }
    Write-FrameRow
    Write-FrameLine $BoxChar.LT $BoxChar.RT
    Write-FrameRow -Left @((Seg '   '), (Seg 'Restart the PC to apply all settings.' 'Yellow')) -Right @((Seg 'Enter' 'Cyan'), (Seg ' close   ' 'DarkGray'))
    Write-FrameLine $BoxChar.BL $BoxChar.BR
    Clear-KeyBuffer
    while ([Console]::ReadKey($true).Key -ne 'Enter') { }
}

$script:Failures = New-Object System.Collections.Generic.List[object]
$script:Run = $null

function Skip([string]$Reason) { $script:StepSkip = $Reason }

function Invoke-Run([scriptblock]$Steps) {
    $script:Run = @{ Counting = $true; Sections = (New-Object System.Collections.Generic.List[object]); Current = -1; Done = 0; Label = ''; Started = (Get-Date) }
    & $Steps
    $script:Run.Counting = $false
    $script:Run.Current = -1
    $script:Run.Started = Get-Date
    Clear-Host
    & $Steps
    if ($script:Run.Current -ge 0) { Complete-Section }
}

function Complete-Section {
    $section = $script:Run.Sections[$script:Run.Current]
    $section.State = 'done'
    $section.Total = $section.Done
}

function Start-Section([string]$Title) {
    $run = $script:Run
    if ($run.Current -ge 0 -and -not $run.Counting) { Complete-Section }
    $index = -1
    for ($i = 0; $i -lt $run.Sections.Count; $i++) { if ($run.Sections[$i].Name -eq $Title) { $index = $i } }
    if ($index -lt 0) {
        $run.Sections.Add(@{ Name = $Title; Total = 0; Done = 0; Ok = 0; Skipped = 0; Failed = 0; State = 'todo' })
        $index = $run.Sections.Count - 1
    }
    $run.Current = $index
    if (-not $run.Counting) { $run.Sections[$index].State = 'run' }
}

function Start-Spinner {
    if (-not $script:SpinnerReady) { return }
    try { [OwNative.Console]::StartSpinner($Spinner, 4, 2 + $script:Run.Current, $FrameWidth - 3, 0, $script:Run.Started) } catch { $null = $_ }
}

function Stop-Spinner {
    if (-not $script:SpinnerReady) { return }
    try { [OwNative.Console]::StopSpinner() } catch { $null = $_ }
}

function Invoke-Step {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][scriptblock]$Action)
    $stepSection = $script:Run.Sections[$script:Run.Current]
    if ($script:Run.Counting) { $stepSection.Total++; return }
    $script:Run.Label = $Label
    Show-RunFrame
    $ErrorActionPreference = 'Stop'
    $script:StepSkip = $null
    Start-Spinner
    try {
        $null = & $Action *>&1
        if ($script:StepSkip) { $stepSection.Skipped++ } else { $stepSection.Ok++ }
    } catch {
        $stepSection.Failed++
        $script:Failures.Add([pscustomobject]@{ Label = $Label; Message = $_.Exception.Message })
    } finally {
        Stop-Spinner
    }
    $stepSection.Done++
    $script:Run.Done++
}

function Invoke-ForEachItem {
    param([object[]]$Items, [scriptblock]$Action, [scriptblock]$Label = { param($Item) "$Item" })
    $failed = @(foreach ($item in $Items) { try { $null = & $Action $item } catch { & $Label $item } })
    if ($failed.Count -gt 0) { throw ('not changed: ' + ($failed -join ', ')) }
}

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
    # Not Win32_Battery: a USB UPS shows up as a battery.
    $chassis = @((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    $isLaptop = ($cs.PCSystemType -eq 2) -or [bool]($chassis | Where-Object { $_ -in 8, 9, 10, 14, 30, 31, 32 })

    $gpus = @(Get-CimInstance -ClassName Win32_VideoController | ForEach-Object {
        [pscustomobject]@{
            Name       = $_.Name
            Vendor     = Get-GpuVendor $_.PNPDeviceID
            IsDiscrete = Test-DiscreteGpuName $_.Name
            IsBasic    = ($_.PNPDeviceID -match 'BasicDisplay' -or $_.Name -match 'Basic Display')
        }
    })

    $isVm = ($cs.Manufacturer -match 'QEMU|VMware|innotek|Xen|Parallels') -or
            ($cs.Model -match 'Virtual|KVM|VMware|VirtualBox|Q35|i440FX')

    $hasLinux = [bool](Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.GptType -eq '{0FC63DAF-8483-4772-8E79-3D69D8477DE4}' })

    [pscustomobject]@{
        IsDualCcdX3D = ($cpu.Name -match 'X3D' -and $cpu.NumberOfCores -gt 8)
        Gpus         = $gpus
        IsLaptop     = $isLaptop
        IsVM         = $isVm
        HasLinux     = $hasLinux
    }
}

function Get-XboxEnabled {
    return [bool](Get-AppxPackage -Name 'Microsoft.GamingApp' -ErrorAction SilentlyContinue)
}

function Get-PrintingEnabled {
    $svc = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
    return ($svc -and $svc.StartType -ne 'Disabled')
}

function Get-VirtualizationEnabled {
    if ((Get-CimInstance -ClassName Win32_ComputerSystem).HypervisorPresent) { return $true }
    return (Test-FeatureEnabled $VirtualizationDisable)
}

function Get-ReturningApps {
    $installed = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    return @($ReturningApps.Keys | Where-Object { $installed -contains $_ })
}

function Assert-Winget {
    if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue) { return }
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction SilentlyContinue
    if (-not (Get-Command -Name 'winget' -ErrorAction SilentlyContinue)) {
        throw 'winget not found: update "App Installer" from the Microsoft Store, then run the script again.'
    }
}

$WingetAlreadyInstalled = -1978335135  # 0x8A150061 (with --no-upgrade)
$WingetNoUpdate         = -1978335189  # 0x8A15002B

function Install-WingetPackage([string]$Id, [string]$Source = 'winget') {
    Assert-Winget
    $arguments = @('install', '--id', $Id, '--exact', '--source', $Source, '--silent', '--no-upgrade',
                   '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    Invoke-Native -File 'winget' -Arguments $arguments -OkCodes @(0, $WingetAlreadyInstalled, $WingetNoUpdate) | Out-Null
    if ($LASTEXITCODE -ne 0) { return (Skip 'already installed') }
}

function Set-FirefoxConfig {
    $firefoxDir = Join-Path $env:ProgramFiles 'Mozilla Firefox'
    if (-not (Test-Path -LiteralPath (Join-Path $firefoxDir 'firefox.exe'))) { return (Skip 'Firefox not found') }
    if ((Test-Path -LiteralPath (Join-Path $firefoxDir 'firefox.cfg')) -and
        (Test-Path -LiteralPath (Join-Path $firefoxDir 'distribution\extensions\uBlock0@raymondhill.net.xpi'))) { return (Skip 'already done') }
    $utf8 = New-Object System.Text.UTF8Encoding($false)

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
defaultPref("browser.startup.page", 3);
defaultPref("browser.ml.chat.enabled", false);
defaultPref("browser.ml.chat.shortcuts", false);
defaultPref("browser.ml.linkPreview.enabled", false);
defaultPref("browser.tabs.groups.smart.enabled", false);
defaultPref("browser.newtabpage.activity-stream.showSponsored", false);
defaultPref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
defaultPref("browser.urlbar.suggest.quicksuggest.sponsored", false);
defaultPref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
defaultPref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
defaultPref("extensions.htmlaboutaddons.recommendations.enabled", false);
defaultPref("extensions.getAddons.showPane", false);
defaultPref("browser.discovery.enabled", false);
defaultPref("browser.tabs.firefox-view", false);
defaultPref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
defaultPref("app.normandy.enabled", false);
defaultPref("datareporting.usage.uploadEnabled", false);
defaultPref("dom.private-attribution.submission.enabled", false);
defaultPref("privacy.globalprivacycontrol.enabled", true);
'@
    [IO.File]::WriteAllText((Join-Path $firefoxDir 'firefox.cfg'), $cfg, $utf8)

    $extDir = Join-Path $firefoxDir 'distribution\extensions'
    $xpi = Join-Path $extDir 'uBlock0@raymondhill.net.xpi'
    if (-not (Test-Path -LiteralPath $xpi)) {
        New-Item -Path $extDir -ItemType Directory -Force | Out-Null
        # Download elsewhere, then move: an interrupted download must not pass the "already done" check.
        $download = Join-Path $env:TEMP 'uBlock0@raymondhill.net.xpi'
        Invoke-WebRequest -Uri 'https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi' -OutFile $download -UseBasicParsing
        Move-Item -LiteralPath $download -Destination $xpi -Force
    }

    Get-ScheduledTask -TaskPath '\Mozilla\' -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -like 'Firefox Default Browser Agent*' } | Disable-ScheduledTask | Out-Null
}

function Add-FirefoxToTaskbar {
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
    New-Item -Path (Split-Path -Parent $TaskbarXml) -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllText($TaskbarXml, $xml, (New-Object System.Text.UTF8Encoding($false)))
    $key = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    Set-RegValue $key 'StartLayoutFile' $TaskbarXml 'ExpandString'
    Set-RegValue $key 'LockedStartLayout' 1
    Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Stop-Process -Force
    $deadline = (Get-Date).AddSeconds(6)
    while ((Get-Date) -lt $deadline -and -not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 300 }
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) { Start-Process 'explorer.exe' }
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
    if (-not @($AppIds | Where-Object { $Selected.Contains($_) })) { return }
    Start-Section 'Applications'

    Invoke-Step 'winget sources' {
        Assert-Winget
        try { Invoke-Native -File 'winget' -Arguments @('source', 'update', '--disable-interactivity') }
        catch {
            Invoke-Native -File 'winget' -Arguments @('source', 'reset', '--force', '--disable-interactivity')
            Invoke-Native -File 'winget' -Arguments @('source', 'update', '--disable-interactivity')
        }
    }
    if (-not (Get-Command -Name 'winget' -ErrorAction SilentlyContinue)) { return }

    if ($Selected.Firefox) {
        $script:FirefoxInstalledNow = $false
        Invoke-Step 'Firefox' {
            Install-WingetPackage 'Mozilla.Firefox.fr'
            $script:FirefoxInstalledNow = -not $script:StepSkip
        }
        Invoke-Step 'Firefox: uBlock Origin and settings' { Set-FirefoxConfig }
        if ($script:FirefoxInstalledNow) { Invoke-Step 'Firefox: pin to the taskbar' { Add-FirefoxToTaskbar } }
    }
    if ($Selected.Vlc) {
        Invoke-Step 'VLC' {
            Install-WingetPackage 'VideoLAN.VLC'
            Remove-Shortcut @('VLC media player.lnk')
        }
    }
    if ($Selected.Steam) {
        Invoke-Step 'Steam' { Install-WingetPackage 'Valve.Steam' }
        Invoke-Step 'Steam: no launch at startup' { Disable-StartupEntry 'Steam' }
    }
    if ($Selected.Discord) {
        Invoke-Step 'Discord' { Install-WingetPackage 'Discord.Discord' }
        Invoke-Step 'Discord: no launch at startup' { Disable-StartupEntry 'Discord' }
    }
}

function Invoke-PrivacySteps {
    Start-Section 'Privacy and telemetry'

    Invoke-Step 'Telemetry and useless services' {
        Invoke-ForEachItem $ServicesToDisable { param($Service) Set-ServiceStartup -Name $Service -Startup Disabled -Stop }
    }

    Invoke-Step 'Telemetry scheduled tasks' {
        Invoke-ForEachItem $TelemetryTasks { param($Task) Disable-TaskByPath $Task } -Label { param($Task) Split-Path -Path $Task -Leaf }
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
    Start-Section 'AI'

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
    Start-Section 'System and services'

    Invoke-Step 'Hibernation' {
        if ($Info.IsLaptop) { return (Skip 'laptop, Windows uses it to protect the battery in standby') }
        Invoke-Native -File 'powercfg.exe' -Arguments @('/hibernate', 'off')
    }

    Invoke-Step 'Background apps' {
        $allowed = @('Microsoft.SecHealthUI_8wekyb3d8bbwe')
        foreach ($name in 'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay') {
            if (Get-AppxPackage -Name $name -ErrorAction SilentlyContinue) { $allowed += "${name}_8wekyb3d8bbwe" }
        }
        Set-RegValue $AppPrivacyKey 'LetAppsRunInBackground' 2
        Set-RegValue $AppPrivacyKey 'LetAppsRunInBackground_ForceAllowTheseApps' ([string[]]$allowed) 'MultiString'
    }

    Invoke-Step 'Peer-to-peer update sharing' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    }

    Invoke-Step 'Remote Assistance' {
        Set-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
    }

    Invoke-Step 'Mobile devices (Cross Device Experience Host)' {
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
    Start-Section 'Power and latency'

    if ($Info.IsLaptop) {
        Invoke-Step 'Power settings' { return (Skip 'laptop, left to the manufacturer') }
        return
    }

    if ($Info.IsDualCcdX3D) {
        Invoke-Step 'Balanced plan (dual-CCD X3D: core parking kept)' {
            Invoke-Native -File 'powercfg.exe' -Arguments @('/setactive', $SchemeBalanced)
        }
    } else {
        Invoke-Step 'Balanced plan + "Best performance" power mode' {
            Invoke-Native -File 'powercfg.exe' -Arguments @('/setactive', $SchemeBalanced)
            try {
                Invoke-Native -File 'powercfg.exe' -Arguments @('/overlaysetactive', $OverlayBestPerf)
            } catch {
                $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
                Set-RegValue $key 'ActiveOverlayAcPowerScheme' $OverlayBestPerf 'String'
                Set-RegValue $key 'ActiveOverlayDcPowerScheme' $OverlayBestPerf 'String'
            }
        }
    }

    Invoke-Step 'PCI Express link state power management' {
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setacvalueindex', $SchemeBalanced, 'SUB_PCIEXPRESS', 'ASPM', '0')
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setdcvalueindex', $SchemeBalanced, 'SUB_PCIEXPRESS', 'ASPM', '0')
    }

    Invoke-Step 'USB selective suspend' {
        $sub = '2a737441-1930-4402-8d77-b2bebba308a3'; $setting = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setacvalueindex', $SchemeBalanced, $sub, $setting, '0')
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setdcvalueindex', $SchemeBalanced, $sub, $setting, '0')
    }

    Invoke-Step 'Wi-Fi power saving' {
        $sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'; $setting = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setacvalueindex', $SchemeBalanced, $sub, $setting, '0')
    }

    Invoke-Step 'Apply the modified power plan' {
        Invoke-Native -File 'powercfg.exe' -Arguments @('/setactive', $SchemeBalanced)
    }

    Invoke-Step 'Network adapter power saving' {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.NdisPhysicalMedium -eq 14 })
        if ($adapters.Count -eq 0) { return (Skip 'no Ethernet adapter') }
        $keywords = @('*EEE', 'EEE', 'AdvancedEEE', 'EnableGreenEthernet', 'GigaLite', 'PowerSavingMode', 'ULPMode')
        $properties = @(foreach ($adapter in $adapters) {
            foreach ($keyword in $keywords) {
                Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -ErrorAction SilentlyContinue |
                    Where-Object { "$($_.RegistryValue)" -ne '0' }
            }
        })
        Invoke-ForEachItem $properties { param($Property) $Property | Set-NetAdapterAdvancedProperty -RegistryValue '0' -NoRestart } -Label {
            param($Property) '{0} ({1})' -f $Property.RegistryKeyword, $Property.Name
        }
    }
}

function Invoke-GamingSteps {
    Start-Section 'Gaming and display'

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
    Start-Section 'Search'

    Invoke-Step 'Document indexing: names and properties only' {
        Invoke-ForEachItem $PropertiesOnlyExtensions {
            param($Extension)
            $key = "HKLM:\SOFTWARE\Classes\$Extension\PersistentHandler"
            $current = Get-RegValue $key '(default)'
            if ($current -eq $NullPersistentHandler) { return }
            if ($current) { Set-RegValue $key 'OriginalPersistentHandler' $current 'String' }
            Set-RegValue $key '(default)' $NullPersistentHandler 'String'
        }
    }
}

function Invoke-EdgeSteps {
    Start-Section 'Microsoft Edge'

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
    Start-Section 'Interface, keyboard and audio'

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
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' ([int]$Enabled)
    }
}

function Invoke-NotificationSteps {
    Start-Section 'Notifications'
    Invoke-Step 'Lock screen notifications, tips and welcome screens' {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
    }
}

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
    foreach ($entry in $XboxStoreIds.GetEnumerator()) {
        $id = $entry.Value
        Invoke-Step ('Install {0}' -f $entry.Key) { Install-WingetPackage -Id $id -Source 'msstore' }
    }
    Invoke-Step 'Xbox controller button: Game Bar' {
        Set-RegValue 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 1
    }
}

function Disable-Printing {
    Invoke-Step 'Print Spooler' { Set-ServiceStartup -Name 'Spooler' -Startup Disabled -Stop }
    Invoke-Step 'Printer configuration service' { Set-ServiceStartup -Name 'PrintDeviceConfigurationService' -Startup Disabled -Stop }
    Invoke-Step 'PDF and XPS virtual printers' { Set-Features $PrintingFeatures $false }
}

function Enable-Printing {
    Invoke-Step 'Print Spooler' { Set-ServiceStartup -Name 'Spooler' -Startup Automatic -Start }
    Invoke-Step 'Printer configuration service' { Set-ServiceStartup -Name 'PrintDeviceConfigurationService' -Startup Manual }
    Invoke-Step 'PDF and XPS virtual printers' { Set-Features $PrintingFeatures $true }
}

function Disable-Virtualization {
    Invoke-Step 'WSL, virtualization platforms, Hyper-V and Sandbox' { Set-Features $VirtualizationDisable $false }
    Invoke-Step 'Hypervisor at boot' {
        Invoke-Native -File 'bcdedit.exe' -Arguments @('/set', 'hypervisorlaunchtype', 'off')
    }
}

function Enable-Virtualization {
    Invoke-Step 'WSL and virtualization platforms' { Set-Features $VirtualizationEnable $true }
    Invoke-Step 'Hypervisor at boot' {
        Invoke-Native -File 'bcdedit.exe' -Arguments @('/set', 'hypervisorlaunchtype', 'auto')
    }
}

function Remove-ReturningApps {
    Invoke-Step 'Remove apps installed again' { Uninstall-StoreApp @(Get-ReturningApps) }
}

function Get-ChangeItems {
    $firstRun = $null -eq (Get-RegValue $AppPrivacyKey 'LetAppsRunInBackground_ForceAllowTheseApps')
    $items = New-Object System.Collections.Generic.List[object]
    $add = {
        param($Label, $Hint, [bool]$Current, $OnId, $OnText, $OffId, $OffText)
        $items.Add(@{ Label = $Label; Hint = $Hint; Current = $Current; Value = ($Current -and -not $firstRun)
                      OnId = $OnId; OnText = $OnText; OffId = $OffId; OffText = $OffText })
    }

    if ($firstRun) {
        & $add 'Firefox + uBlock Origin' 'With the uBlock Origin ad blocker, without telemetry or sponsored content. Pinned to the taskbar.' $false 'Firefox' 'install Firefox' $null $null
        & $add 'VLC' 'Plays any video or audio file.' $false 'Vlc' 'install VLC' $null $null
        & $add 'Steam' 'Installed with winget, not launched at startup.' $false 'Steam' 'install Steam' $null $null
        & $add 'Discord' 'Installed with winget, not launched at startup.' $false 'Discord' 'install Discord' $null $null
    }

    & $add 'Xbox (Xbox app, Game Pass, Game Bar)' 'Needed for Game Pass. Unchecked: removed, controllers keep working.' (Get-XboxEnabled) 'XboxOn' 'install Xbox' 'XboxOff' 'remove Xbox'
    & $add 'Printing' 'Print services and PDF/XPS virtual printers. Unchecked: disabled.' (Get-PrintingEnabled) 'PrintingOn' 'enable printing' 'PrintingOff' 'disable printing'
    & $add 'WSL / virtualization' 'Docker Desktop, WSL2 and Android emulators. Unchecked: disabled.' (Get-VirtualizationEnabled) 'VirtOn' 'enable WSL' 'VirtOff' 'disable WSL'
    & $add 'Notifications' 'Discord, Steam, Windows Update, Windows Security. Unchecked: no notifications at all.' (Get-NotificationsEnabled) 'NotificationsOn' 'turn on notifications' 'NotificationsOff' 'turn off all notifications'

    $returning = @(Get-ReturningApps)
    if ($returning.Count -gt 0) {
        $names = ($returning | ForEach-Object { $ReturningApps[$_] }) -join ', '
        & $add "$names (installed again by Windows)" 'Removed by the USB key, installed again since by Windows Update or the Store. Unchecked: removed.' $true $null $null 'ReturningApps' "remove $names"
    }
    return $items.ToArray()
}

function Get-SelectedChanges($Items) {
    $selected = [ordered]@{}
    foreach ($item in $Items) {
        if ($item.Value -and -not $item.Current -and $item.OnId) { $selected[$item.OnId] = $item.OnText }
        if (-not $item.Value -and $item.Current -and $item.OffId) { $selected[$item.OffId] = $item.OffText }
    }
    return $selected
}

function Invoke-ChangeSteps($Selected, [bool]$KeepGameBar) {
    $changes = @($Selected.Keys | Where-Object { $_ -notin $AppIds })
    if ($changes.Count -eq 0) { return }
    Start-Section 'Changes'
    if ($Selected.XboxOff) { Disable-Xbox -KeepGameBar $KeepGameBar }
    if ($Selected.XboxOn) { Enable-Xbox }
    if ($Selected.PrintingOff) { Disable-Printing }
    if ($Selected.PrintingOn) { Enable-Printing }
    if ($Selected.VirtOff) { Disable-Virtualization }
    if ($Selected.VirtOn) { Enable-Virtualization }
    if ($Selected.NotificationsOff) { Set-Notifications $false }
    if ($Selected.NotificationsOn) { Set-Notifications $true }
    if ($Selected.ReturningApps) { Remove-ReturningApps }
}

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

function Add-Check([string]$Level, [string]$Message, [string]$Advice) {
    $script:Checks.Add([pscustomobject]@{ Level = $Level; Message = $Message; Advice = $Advice })
}

function Get-HealthChecks($Info) {
    $script:Checks = New-Object System.Collections.Generic.List[object]

    $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg -and $dg.VirtualizationBasedSecurityStatus -eq 2) {
        Add-Check 'warn' 'VBS / memory integrity still running' 'Windows Security > Device security > Core isolation: turn off, then restart'
    } else {
        Add-Check 'ok' 'VBS disabled'
    }

    if ($Info.IsVM) {
        Add-Check 'info' 'Virtual machine: hardware checks skipped'
        return $script:Checks.ToArray()
    }

    try {
        if (Confirm-SecureBootUEFI) {
            $db = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name db).Bytes)
            if ($db -match 'Windows UEFI CA 2023') { Add-Check 'ok' 'Secure Boot enabled, 2023 certificates present' }
            else { Add-Check 'warn' 'Secure Boot enabled, 2023 certificates missing' 'Install all Windows updates, then update the BIOS' }
        } else {
            Add-Check 'warn' 'Secure Boot disabled' 'Required by the anti-cheat of Valorant, League of Legends, Battlefield...'
        }
    } catch {
        Add-Check 'info' 'Secure Boot not supported (legacy BIOS / CSM)'
    }

    if (-not $Info.IsLaptop) {
        $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory)
        if ($modules.Count -gt 0) {
            $speed = [int]($modules | Measure-Object -Property ConfiguredClockSpeed -Maximum).Maximum
            $parts = @($modules | ForEach-Object { ([string]$_.PartNumber).Trim() } | Where-Object { $_ } | Select-Object -Unique)
            $label = 'RAM at {0} MT/s' -f $speed
            if ($parts.Count -gt 0) { $label += ' (kit: {0})' -f ($parts -join ', ') }
            $jedec = [int]($modules | Measure-Object -Property Speed -Minimum).Minimum
            if ($jedec -gt 0 -and $speed -gt $jedec) {
                Add-Check 'ok' ($label + ', EXPO/XMP active')
            } else {
                Add-Check 'info' ($label + ', no EXPO/XMP profile detected') 'If the kit is rated faster, enable EXPO (AMD) or XMP (Intel) in the BIOS'
            }
        }

        $integrated = @($Info.Gpus | Where-Object { -not $_.IsDiscrete -and -not $_.IsBasic -and ($_.Vendor -eq 'AMD' -or $_.Vendor -eq 'Intel') })
        if ($integrated.Count -gt 0 -and @($Info.Gpus | Where-Object { $_.IsDiscrete }).Count -gt 0) {
            $installed = ($modules | Measure-Object -Property Capacity -Sum).Sum
            $visible = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
            $reserved = [math]::Max(0, [math]::Round(($installed - $visible) / 1GB, 1))
            Add-Check 'info' ('Integrated graphics enabled ({0}), {1} GB of RAM reserved' -f $integrated[0].Name, $reserved) 'Not used for video encoding or an extra display? Disable it in the BIOS'
        }
    }

    foreach ($gpu in $Info.Gpus) {
        if ($gpu.IsBasic) {
            Add-Check 'warn' "Microsoft basic display driver ($($gpu.Name))" 'Install the driver with NVIDIA App or AMD Adrenalin'
        } elseif ($gpu.IsDiscrete) {
            Add-Check 'ok' "Graphics driver installed: $($gpu.Name)"
        }
    }

    try {
        Initialize-DisplayHelper
        foreach ($d in [OwDisplayInfo]::Get()) {
            $label = 'Display {0}x{1} at {2} Hz' -f $d.Width, $d.Height, $d.CurrentHz
            if ($d.MaxHz -gt $d.CurrentHz) {
                Add-Check 'warn' $label ('{0} Hz available: Settings > System > Display > Advanced display' -f $d.MaxHz)
            } else {
                Add-Check 'ok' $label
            }
        }
    } catch {
        Add-Check 'info' 'Displays: cannot be checked'
    }
    return $script:Checks.ToArray()
}

function Start-Run {
    if (Test-RebootPending) { Wait-Exit 'A restart is pending (Windows Update). Restart the PC, then run the script again.' }

    Show-Loading
    $info = Get-SystemInfo
    $items = @(Get-ChangeItems)
    if (-not (Read-Selection $items)) { exit 0 }
    $selected = Get-SelectedChanges $items

    $keepGameBar = $false
    if ($selected.XboxOff -and $info.IsDualCcdX3D) {
        $keepGameBar = Read-FrameYesNo 'KEEP THE GAME BAR?' @('Your X3D processor uses the Game Bar to send games to the right CCD.')
    }

    Invoke-Run {
        Invoke-AppSteps $selected
        Invoke-ChangeSteps $selected $keepGameBar
        Invoke-PrivacySteps
        Invoke-AiSteps
        Invoke-SystemSteps $info
        Invoke-PowerSteps $info
        Invoke-GamingSteps
        Invoke-SearchSteps
        Invoke-EdgeSteps
        Invoke-InterfaceSteps
        Invoke-NotificationSteps
        Start-Section 'Microsoft Store'
        Invoke-Step 'Store app updates (in the background)' { Start-StoreUpdates }
    }

    $script:Run.Label = 'Health check'
    Show-RunFrame
    Show-FinalFrame @(Get-HealthChecks $info)
    exit 0
}

Start-Run
