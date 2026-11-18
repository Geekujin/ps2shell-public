<#
.SYNOPSIS
    PowerShell profile used by me for both fun and profit.

.DESCRIPTION
    Profile to customise your PowerShell environment. Loads bespoke config and variables from profile_config.json file. 
	
.VERSION
    0.1
#>


# Start a timer to measure profile load times
$ProfileLoadTime = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "`nLoading profile...`n" -ForeGroundColor DarkGray


# === [GLOBAL CONFIGURATION] === #

# Assign a path to the global configuration file
$ConfigFilePath = Join-Path $PSScriptRoot '.config\profile_config.json'

# Specify log directory in case config fails to load
$LogDir = Join-Path $PSScriptRoot 'logs'

# Command history file
$Global:CommandHistoryFile = Join-Path $LogDir 'history.jsonl'
$script:LastLoggedHistoryId = -1

# Commands matching this pattern are written to the history file as [redacted]
$script:HistoryRedactPattern = '(?i)(password|passwd|secret|token|api[_-]?key|bearer|-AsPlainText|ConvertTo-SecureString|BW_SESSION|bw\s+(unlock|login|get))'


# Sets the script encoding to UTF8 for handling emoji
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8


# === [FUNCTIONS] === #

# Profile Initialisation and Logging
function Write-ProfileLog {
    <#
    .SYNOPSIS
        Writes a line to the ps2shell profile log.
    .DESCRIPTION
        Appends a timestamped entry to ps2shell_profile.log in the log folder. DEBUG entries are
        only written when settings.debug is true. Fails silently if the log folder doesn't exist.
    .PARAMETER Message
        The text to log.
    .PARAMETER Level
        DEBUG, INFO, WARN, ERROR or FATAL. Defaults to INFO.
    #>
    param(
        [string]$Message,

        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
        [string]$Level = 'INFO'
    )

    # Skip DEBUG messages unless debug mode is enabled
    if ($Level -eq 'DEBUG' -and -not $Global:Config.Settings.Debug) {
        return
    }

    # Fails gracefully if the path is empty or doesn't exist
    if ([string]::IsNullOrWhiteSpace($LogDir) -or -not (Test-Path -LiteralPath $LogDir)) {
        return
    }

    $LogFile = Join-Path $LogDir "ps2_profile.log"
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    try {
        "[$Timestamp] [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

Write-ProfileLog -Message "============ Profile Loading ============"

function Measure-ProfileStep {
    <#
    .SYNOPSIS
        Shows how long the profile has taken to load so far (debug mode only).
    .PARAMETER Name
        Label for this step.
    #>
    param([string]$Name)

    if (-not $Global:Config.Settings.Debug) {
        return
    }

    $Message = "Profile Step Timer: {0,-30} {1,6} ms" -f $Name, $ProfileLoadTime.ElapsedMilliseconds

    Write-Host $Message -ForegroundColor DarkGray
    Write-ProfileLog -Level DEBUG -Message $Message
}

function Test-InteractiveSession { # Returns $false when the shell can't prompt the user (scheduled tasks, -NonInteractive, etc.)
    <#
    .SYNOPSIS
        Returns `$true if this shell can prompt the user.
    .DESCRIPTION
        Returns `$false for non-interactive sessions such as scheduled tasks or pwsh -NonInteractive,
        so update checks and vault prompts don't hang them.
    #>
    if (-not [Environment]::UserInteractive) {
        return $false
    }

    $NonInteractiveArgs = [Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-noni' }
    return (-not $NonInteractiveArgs)
}

function Get-ProfileConfig {
    <#
    .SYNOPSIS
        Loads and parses the ps2shell configuration file.
    .PARAMETER Path
        Path to profile_config.json. Defaults to .config\profile_config.json.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $ConfigFilePath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found at: $Path (copy .config\profile_config.example.json to get started)"
    }

    try {
        # Read as UTF8 explicitly so Windows PowerShell 5.1 handles the ArtTheme characters
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        throw "Failed to parse JSON in ${Path}: $($_.Exception.Message)"
    }
}

function Add-PathEntry { # Appends a folder to a PATH-style variable once, so reloading doesn't keep growing it
    <#
    .SYNOPSIS
        Adds a folder to PATH (or another PATH-style variable) once.
    .DESCRIPTION
        Skips the folder if it's already listed, so reloading the profile doesn't keep growing PATH.
    .PARAMETER Variable
        Environment variable to change, e.g. PATH or PSModulePath.
    .PARAMETER Entry
        The folder to add. Empty values are ignored.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Variable,

        [string]$Entry
    )

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return
    }

    $Separator = [System.IO.Path]::PathSeparator
    $Current = [Environment]::GetEnvironmentVariable($Variable, 'Process')
    $Parts = @($Current -split [regex]::Escape($Separator) | Where-Object { $_ })
    $Normalised = $Entry.TrimEnd('\', '/')

    if ($Parts | Where-Object { $_.TrimEnd('\', '/') -eq $Normalised }) {
        return
    }

    [Environment]::SetEnvironmentVariable($Variable, (($Parts + $Normalised) -join $Separator), 'Process')
}


# === [PROFILE CONFIG] === #

# Load Profile Configuration
try {
    $Global:Config = Get-ProfileConfig
} catch {
    Write-Host "`n[!] Profile initialization aborted: $($_.Exception.Message)`n" -ForegroundColor Red
    Write-ProfileLog -Level FATAL -Message "Configuration failed to load: $($_.Exception.Message)"
    return
}

# Prefer the log folder from the config once it's available
if (-not [string]::IsNullOrWhiteSpace($Config.Settings.LogFolder)) {
    $LogDir = $Config.Settings.LogFolder
    $Global:CommandHistoryFile = Join-Path $LogDir 'history.jsonl'
}

Write-ProfileLog -Level DEBUG -Message "Debug logging enabled"
Measure-ProfileStep "Configuration loading"

# Add Script and Module folders to Path variables
Add-PathEntry -Variable 'PSModulePath' -Entry $Config.Settings.ModuleRoot
Write-ProfileLog -Level DEBUG -Message "Module Path updated to $env:PSModulePath"
Add-PathEntry -Variable 'PATH' -Entry $Config.Settings.ScriptRoot
Add-PathEntry -Variable 'PATH' -Entry $Config.Settings.ExeFolder
Write-ProfileLog -Level DEBUG -Message "PATH updated to $env:PATH"
$host.ui.RawUI.WindowTitle = $Config.Settings.WindowTitle # Rename the Titlebar/Tab


# === [SECRETS] === #
try {
    Import-Module PS2Bitwarden -ErrorAction Stop
    Write-ProfileLog -Level DEBUG -Message "PS2Bitwarden loaded"
} catch {
    Write-Warning "Secrets module failed to load: $($_.Exception.Message)"
    Write-ProfileLog -Level ERROR -Message "PS2Bitwarden failed to load: $($_.Exception.Message)"
}
Measure-ProfileStep "Secrets module loaded"

# === [UPDATER] === #
# Code and functions to update the profile and config go here


# Profile Helpers
function Reload-Profile { # Reloads the PowerShell profile
    <#
    .SYNOPSIS
        Reloads the PowerShell profile.
    .DESCRIPTION
        This function reloads the PowerShell profile by sourcing the profile script. 
        Useful after updating the profile or making changes to the configuration.
    #>
    Clear-Host
    try {
        . $Global:Config.Settings.Profilepath
        Write-Host "`nProfile reloaded successfully." -ForegroundColor Cyan
        Write-ProfileLog -Message "Profile reloaded." -Level DEBUG
    } catch {
        Write-Host "`nError loading profile: $($_.Exception.Message)" -ForegroundColor Red
        Write-ProfileLog -Message "Error loading profile: $($_.Exception.Message)" -Level ERROR
    }
}

function Get-PS2ShellHelp {
    <#
    .SYNOPSIS
        Displays help for PS2Shell profile functions.
    .DESCRIPTION
        Run without parameters to see a list of all functions defined by the profile.
        Pass a function name to view its full PowerShell help documentation.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position=0)]
        [string]$FunctionName
    )

    if (-not [string]::IsNullOrWhiteSpace($FunctionName)) {
        Get-Help $FunctionName -Detailed
        return
    }

    Write-Host "`n=== PS2Shell Functions ===`n" -ForegroundColor Cyan

    Get-Command -CommandType Function |
        Where-Object { $_.ScriptBlock.File -eq $PSCommandPath } |
        Sort-Object Name |
        ForEach-Object {
            $Synopsis = (Get-Help $_.Name -ErrorAction SilentlyContinue).Synopsis
            # Get-Help returns the syntax line when there's no synopsis, so hide that
            if ([string]::IsNullOrWhiteSpace($Synopsis) -or $Synopsis.Trim().StartsWith($_.Name)) { $Synopsis = '' }
            Write-Host ("  {0,-28}" -f $_.Name) -ForegroundColor Green -NoNewline
            Write-Host $Synopsis.Trim() -ForegroundColor Gray
        }

    Write-Host "`nRun 'Get-PS2ShellHelp <FunctionName>' for detailed syntax.`n" -ForegroundColor DarkGray
}

# Keep credential-looking commands out of PSReadLine's own history file too
if (Get-Module PSReadLine) {
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$Line)
        $Line -notmatch $script:HistoryRedactPattern
    }
}


# Network Information
function Get-NetworkInfo { # Returns host name, LAN IP and VPN IP (and optionally the network profile name)
    <#
    .SYNOPSIS
        Returns the host name, LAN IP and VPN IP of this machine.
    .PARAMETER IncludeNetworkName
        Also look up the connected network profile name (slower).
    #>
    [CmdletBinding()]
    param([switch]$IncludeNetworkName)

    $VpnPattern = 'VPN|WireGuard|Fortinet|TAP|TUN'
    $PhysicalIP = $null
    $VpnIP      = $null

    $Interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object {
            $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
            $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback
        }

    foreach ($Interface in $Interfaces) {
        $IPv4 = $Interface.GetIPProperties().UnicastAddresses |
            Where-Object { $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            Select-Object -First 1

        if (-not $IPv4) {
            continue
        }

        $Address = $IPv4.Address.IPAddressToString
        if ($Address -eq '127.0.0.1' -or $Address.StartsWith('169.254.')) {
            continue
        }

        if ($Interface.Description -match $VpnPattern) {
            if (-not $VpnIP) { $VpnIP = $Address }
            continue
        }

        if (
            $Interface.Description -notmatch 'Hyper-V|Virtual' -and
            $Interface.Name -notmatch 'vEthernet|Default Switch'
        ) {
            if (-not $PhysicalIP) { $PhysicalIP = $Address }
        }
    }

    $NetworkName = $null
    if ($IncludeNetworkName -and (Get-Command Get-NetConnectionProfile -ErrorAction SilentlyContinue)) {
        $NetworkName = Get-NetConnectionProfile -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' } |
            Select-Object -First 1 -ExpandProperty Name
    }

    [PSCustomObject]@{
        HostName    = [System.Net.Dns]::GetHostName()
        NetworkName = if ($NetworkName) { $NetworkName } else { 'Unknown' }
        PhysicalIP  = if ($PhysicalIP) { $PhysicalIP } else { 'Unknown' }
        VPNIP       = $VpnIP
    }
}

function Show-Network { # Draws the host / LAN / VPN box on the start screen
    <#
    .SYNOPSIS
        Draws the HOST / LAN / VPN box shown on the start screen.
    #>
    $Info = Get-NetworkInfo
    $VPNIP = if ($Info.VPNIP) { $Info.VPNIP } else { 'Not Connected' }

    # Box characters
    $TL = '┍'
    $TR = '┑'
    $BL = '└'
    $BR = '┘'
    $H  = '─'
    $V  = '│'

    # Colours
    $BoxColor   = 'DarkGray'
    $LabelColor = 'DarkCyan'
    $InfoColor  = 'Gray'
    $BreakColor = 'DarkGray'

    $ContentLength =
        (' HOST: '.Length + $Info.HostName.Length) +
        (' | LAN: '.Length + $Info.PhysicalIP.Length) +
        (' | VPN: '.Length + $VPNIP.Length) + 1

    Write-Host "$TL$($H * $ContentLength)$TR" -ForegroundColor $BoxColor
    Write-Host $V -NoNewline -ForegroundColor $BoxColor

    Write-Host " HOST: " -NoNewline -ForegroundColor $LabelColor
    Write-Host $Info.HostName -NoNewline -ForegroundColor $InfoColor
    Write-Host " | " -NoNewline -ForegroundColor $BreakColor

    Write-Host "LAN: " -NoNewline -ForegroundColor $LabelColor
    Write-Host $Info.PhysicalIP -NoNewline -ForegroundColor $InfoColor
    Write-Host " | " -NoNewline -ForegroundColor $BreakColor

    Write-Host "VPN: " -NoNewline -ForegroundColor $LabelColor
    Write-Host $VPNIP -NoNewline -ForegroundColor $InfoColor
    Write-Host " " -NoNewline

    Write-Host $V -ForegroundColor $BoxColor
    Write-Host "$BL$($H * $ContentLength)$BR" -ForegroundColor $BoxColor
}

# Profile display and visuals
function Prompt { # Customised command prompt
    <#
    .SYNOPSIS
        The PS2Shell prompt: time, current folder and computer name.
    .DESCRIPTION
        Also writes each command to the history file (see Get-CommandHistory).
    #>
    # Capture the last command's result before anything else here overwrites $?
    $LastCommandSucceeded = $?

    $Time = Get-Date -Format "HH:mm:ss"
	$CurrPath = (Get-Location).Path


    # Write command history to file
    Write-CommandHistory -Success $LastCommandSucceeded
	
	# Replace the home directory with ~
	$CurrPath = $CurrPath -replace ('^' + [regex]::Escape($Global:Config.Settings.Home)), '~'

	Write-Host "`n[$Time] " -NoNewline
    Write-Host "$($Global:Config.Settings.Name)@" -Foregroundcolor Green -NoNewline
    Write-Host $env:COMPUTERNAME -Foregroundcolor Green -NoNewline
	Write-Host ":" -NoNewline
	Write-Host $CurrPath -ForegroundColor Blue -NoNewline


    # Return the actual prompt symbol
    return "$ "
}

function Get-TimeOfDay { # Returns Morning, Afternoon or Night
    <#
    .SYNOPSIS
        Returns morning, afternoon, evening or night for the greeting.
    #>
    $hour = (Get-Date).Hour

    if ($hour -ge 5 -and $hour -lt 12) {
        return "morning"
    } elseif ($hour -ge 12 -and $hour -lt 16) {
        return "afternoon"
    } elseif ($hour -ge 16 -and $hour -lt 22) {
        return "evening"
    } else {
        return "night"
    }
}

function Write-ColorMappedArt { # Maps specific colours to specific characters
    <#
    .SYNOPSIS
        Prints ASCII art with each character coloured by the chosen ArtTheme.
    .PARAMETER Text
        The art to print.
    .PARAMETER DefaultColor
        Colour for characters the theme doesn't map.
    .PARAMETER Theme
        Name of a theme from ArtThemes in the config. Defaults to Standard.
    #>
    param(
        [string]$Text,
        [ConsoleColor]$DefaultColor = "Gray",
        [string]$Theme = "Standard"
    )

    if ($Global:ArtThemes.ContainsKey($Theme)) {
        $ColorMap = $Global:ArtThemes[$Theme]
    } else {
        Write-Warning "Theme '$Theme' not found. Using Standard."
        $ColorMap = $Global:ArtThemes["Standard"]
    }

    # Group runs of same-coloured characters so we call Write-Host per run, not per character
    $Run = [System.Text.StringBuilder]::new()
    $RunColor = $null

    foreach ($Char in $Text.ToCharArray()) {
        $CharStr = [string]$Char

        if ($CharStr -eq "`r") { continue } # Skip carriage returns

        if ($CharStr -eq "`n") {
            if ($Run.Length -gt 0) { Write-Host $Run.ToString() -NoNewline -ForegroundColor $RunColor; [void]$Run.Clear() }
            Write-Host ""
            continue
        }

        $Color = if ($ColorMap -and $ColorMap.ContainsKey($CharStr)) { $ColorMap[$CharStr] } else { $DefaultColor }

        if ($Run.Length -gt 0 -and $Color -ne $RunColor) {
            Write-Host $Run.ToString() -NoNewline -ForegroundColor $RunColor
            [void]$Run.Clear()
        }

        $RunColor = $Color
        [void]$Run.Append($CharStr)
    }

    if ($Run.Length -gt 0) { Write-Host $Run.ToString() -NoNewline -ForegroundColor $RunColor }

    # Final newline to reset
    Write-Host ""
}

function Get-DateWithOrdinal { # Gets current date with st, nd, rd, th etc.
    <#
    .SYNOPSIS
        Returns today's date as e.g. "Thursday the 29th of October 2026".
    #>
    $date = Get-Date
    $day = $date.Day
    switch ($day % 10) {
        1 { $suffix = if ($day -eq 11) { "th" } else { "st" } }
        2 { $suffix = if ($day -eq 12) { "th" } else { "nd" } }
        3 { $suffix = if ($day -eq 13) { "th" } else { "rd" } }
        default { $suffix = "th" }
    }
    "$($date.ToString('dddd')) the $day$suffix of $($date.ToString('MMMM')) $($date.Year)"
}

function Show-MOTD { # Displays a random message from a motd.txt file
    <#
    .SYNOPSIS
        Displays a random message from a motd.txt file.

    .DESCRIPTION
        Messages in motd.txt should be one per line.
    #>

    # Set the path of the file containing your messages
    $SettingsFolder = if ($Config.Settings.SettingsFolder) { $Config.Settings.SettingsFolder } else { Join-Path $PSScriptRoot '.config' }
    $MOTDFile = Join-Path $SettingsFolder 'motd.txt'

    $SourceColor = "DarkYellow"

    # Check if the file exists
    if (Test-Path -LiteralPath $MOTDFile) {
        $Lines = @(Get-Content -LiteralPath $MOTDFile -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })
        if ($Lines.Count -gt 0) {
            $RandomLine = Get-Random -InputObject $Lines

            Write-Host "Message of the Day`n" -ForegroundColor Cyan

            # Check if the line matches the format of "Quote" - Source, else treat as a message
            if ($RandomLine -match '^"(.+)"\s*-\s*(.+)$') {
                Write-Host "`"$($Matches[1])`"" -ForegroundColor White
                Write-Host " - $($Matches[2])`n" -ForegroundColor $SourceColor
            } else {
                Write-Host "$RandomLine`n" -ForegroundColor White
            }
        } else {
            Write-Warning "No content found in the file."
        }
    } else {
        Write-Host ""
        Write-Warning "File not found at $MOTDFile`n"
        Write-ProfileLog -Level ERROR -Message "Show-MOTD: File not found at $MOTDFile"
    }
}

function Write-CommandHistory {
    <#
    .SYNOPSIS
        Appends the last command to the persistent history file.
    .DESCRIPTION
        Called by the prompt. Commands that look like they contain a credential are saved as [redacted].
    .PARAMETER Success
        Whether the command succeeded.
    #>
    param([bool]$Success = $true)

    $errorMessage = $null

    if (-not $Success -and $Error.Count -gt 0) {
        $errorMessage = $Error[0].Exception.Message
    }

    # Get the most recent history entry
    $history = Get-History -Count 1

    if (-not $history) {
        return
    }

    # Prevent duplicate logging
    if ($history.Id -eq $script:LastLoggedHistoryId) {
        return
    }

    $script:LastLoggedHistoryId = $history.Id

    # Don't log history queries
    if (
        $history.CommandLine -match '^\s*Get-CommandHistory\b' -or
        $history.CommandLine -match '^\s*h\b'
    ) {
        return
    }

    # Don't write anything that looks like a credential to disk
    $command = $history.CommandLine
    if ($command -match $script:HistoryRedactPattern) {
        $command = '[redacted: possible credential]'
        $errorMessage = $null
    }

    $record = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString('o')
        HistoryId = $history.Id
        Status    = if ($Success) { 'OK' } else { 'ERROR' }
        Command   = $command
        Error     = $errorMessage
    }

    try {
        $record |
            ConvertTo-Json -Compress |
            Add-Content -LiteralPath $Global:CommandHistoryFile -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Never let history logging break the prompt
    }
}

function Get-CommandHistory {
    <#
    .SYNOPSIS
        Searches the persistent PS2Shell command history.
    .DESCRIPTION
        Reads Logs\history.jsonl, which keeps commands across sessions with their time and status.
    .PARAMETER Last
        Show the last N commands. Defaults to 20.
    .PARAMETER Date
        Show commands from this day.
    .PARAMETER From
        Start of a date range.
    .PARAMETER To
        End of a date range.
    .PARAMETER Search
        Plain text to look for in commands and errors.
    .PARAMETER Raw
        Only output the command text.
    .PARAMETER ErrorsOnly
        Only show commands that failed.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Last')]
    param (

        [Parameter(ParameterSetName = 'Last')]
        [ValidateRange(1,2147483647)]
        [int]$Last = 20,

        [Parameter(Mandatory, ParameterSetName = 'Date')]
        [datetime]$Date,

        [Parameter(Mandatory, ParameterSetName = 'Range')]
        [datetime]$From,

        [Parameter(Mandatory, ParameterSetName = 'Range')]
        [datetime]$To,

        [Parameter(Mandatory, ParameterSetName = 'Search')]
        [string]$Search,

        [switch]$Raw,

        [switch]$ErrorsOnly
    )

    if (-not (Test-Path -LiteralPath $Global:CommandHistoryFile)) {
        Write-Warning "History file not found: $Global:CommandHistoryFile"
        return
    }

    $history = Get-Content -LiteralPath $Global:CommandHistoryFile -Encoding UTF8 | ConvertFrom-Json

    switch ($PSCmdlet.ParameterSetName) {

        'Last' {
            $history = $history | Select-Object -Last $Last
        }

        'Date' {
            $targetDate = $Date.Date

            $history = $history | Where-Object {
                ([datetime]$_.Timestamp).Date -eq $targetDate
            }
        }

        'Range' {
            $history = $history | Where-Object {
                $timestamp = [datetime]$_.Timestamp
                $timestamp -ge $From -and $timestamp -le $To
            }
        }

        'Search' {
            # Plain-text search, so characters like ( or * don't need escaping
            $history = $history | Where-Object {
                $_.Command -like "*$Search*" -or $_.Error -like "*$Search*"
            }
        }
    }

    if ($ErrorsOnly) {
        $history = $history | Where-Object {
            $_.Status -eq 'ERROR'
        }
    }

    if ($Raw) {
        $history | Select-Object Command
    } else {
        $history | Sort-Object Timestamp | Select-Object @{N='Time';E={[datetime]$_.Timestamp}}, Status, Command, Error
    }
}

Measure-ProfileStep "Functions Loaded"

# === [Profile Setup] ===
if ($Global:Config.Features.UpdateProfile) {
    Update-Profile
}

Measure-ProfileStep "Updates Checked"

# Load Modules
if ($Global:Config.Modules) {
    Write-Host "Importing modules... `n" -ForegroundColor DarkGray
    foreach ($Module in $Global:Config.Modules) {
        try {
            Import-Module $Module -ErrorAction Stop
            Write-Host "Imported module: $Module" -ForegroundColor DarkGray
            Write-ProfileLog -Level DEBUG -Message "Imported module: $Module"
        } catch {
            Write-Warning "Failed to import module: $Module - $($_.Exception.Message)"
            Write-ProfileLog -Level WARN -Message "Failed to import module: $Module - $($_.Exception.Message)"
        }
    }
}

Measure-ProfileStep "Module Loading Complete"

# === [Dot source external scripts] ===
if ($Global:Config.DotSourceFiles) {
    Write-Host "Dot-sourcing scripts...`n" -ForegroundColor DarkGray
    $DefaultRoot = $Global:Config.Settings.ScriptRoot

    foreach ($Entry in $Global:Config.DotSourceFiles) {

        # Logic: If it's a full path (e.g. C:\...), use it.
        # Otherwise, combine it with the ScriptRoot.
        if ([System.IO.Path]::IsPathRooted($Entry)) {
            $FullPath = $Entry
        } else {
            $FullPath = Join-Path -Path $DefaultRoot -ChildPath $Entry
        }
        $FileName = Split-Path -Path $FullPath -Leaf

        # Attempt to load
        if (Test-Path -LiteralPath $FullPath) {
            try {
                . $FullPath
                Write-Host " [+] Loaded script: $FileName" -ForegroundColor DarkGray
            } catch {
                Write-Warning "[!] Failed to load '$FullPath': $($_.Exception.Message)"
                Write-ProfileLog -Level ERROR -Message "Failed to dot-source '$FullPath': $($_.Exception.Message)"
            }
        } else {
            Write-Warning "[?] Script not found: $FullPath"
        }
    }
    Write-Host "`nFinished loading files.`n" -ForegroundColor DarkGray
}
Measure-ProfileStep "Scripts Dot Sourced"


# === [Variables] ===

# Hashtable of ArtColors from config json
$Global:ArtThemes = @{}
if ($Global:Config.ArtThemes) {
    foreach ($themeProp in $Global:Config.ArtThemes.PSObject.Properties) {
        $themeMap = @{}

        foreach ($charProp in $themeProp.Value.PSObject.Properties) {
            $themeMap[$charProp.Name] = $charProp.Value
        }

        $Global:ArtThemes[$themeProp.Name] = $themeMap
    }
}
Measure-ProfileStep "ArtTheme Variables Loaded"

# Hashtable mapping the Network name to Lat/Long and friendly name
$Global:LocationMap = @{}
if ($Config.NetworkLocations) {
    foreach ($entry in $Config.NetworkLocations.PSObject.Properties.Value) {
        $Global:LocationMap[$entry.Name] = @{
            Latitude  = $entry.Latitude
            Longitude = $entry.Longitude
            Name      = $entry.Location
        }
    }
}

Measure-ProfileStep "LocationMap Variables Loaded"

# Time and date variables
$LongDate = Get-DateWithOrdinal
$Greeting = Get-TimeOfDay

Measure-ProfileStep "DateTime Variables Loaded"

$ShellBanner = @"

 ███████████   █████████   ████████          █████████  █████               ████  ████ 
░░███░░░░░███ ███░░░░░███ ███░░░░███        ███░░░░░███░░███               ░░███ ░░███ 
 ░███    ░███░███    ░░░ ░░░    ░███       ░███    ░░░  ░███████    ██████  ░███  ░███ 
 ░██████████ ░░█████████    ███████  ██████░░█████████  ░███░░███  ███░░███ ░███  ░███ 
 ░███░░░░░░   ░░░░░░░░███  ███░░░░  ░░░░░░  ░░░░░░░░███ ░███ ░███ ░███████  ░███  ░███ 
 ░███         ███    ░███ ███      █        ███    ░███ ░███ ░███ ░███░░░   ░███  ░███ 
 █████       ░░█████████ ░██████████       ░░█████████  ████ █████░░██████  █████ █████
░░░░░         ░░░░░░░░░  ░░░░░░░░░░         ░░░░░░░░░  ░░░░ ░░░░░  ░░░░░░  ░░░░░ ░░░░░ 
"@


# ==== [Aliases] ====

# Old names kept so existing configs and habits still work
#Set-Alias -Name Reload-Profile -Value Restart-PS2ShellProfile -Scope Global -Force
Set-Alias -Name Profile-Help -Value Get-PS2ShellHelp -Scope Global -Force

if ($Global:Config.Aliases) {
    Write-Host "Mapping aliases...`n" -ForegroundColor DarkGray
    foreach ($alias in $Global:Config.Aliases.PSObject.Properties) {
        $Name = $alias.Name
        $Value = $alias.Value

        try {
            Set-Alias -Name $Name -Value $Value -Scope Global -Force -ErrorAction Stop
            Write-Host " [+] Alias set: $Name -> $Value" -ForegroundColor DarkGray
        } catch {
            Write-Warning " [!] Failed to set alias '$Name': $($_.Exception.Message)"
        }
    }
    Write-Host "`nFinished mapping aliases.`n" -ForegroundColor DarkGray
}

Measure-ProfileStep "Aliases Loaded"

# === [Main Script Execution] ===
Clear-Host
if ($Global:Config.Features.ShowBanner) {
    Write-ColorMappedArt -Text $ShellBanner -Theme "Standard"
    Write-Host " "
}

if ($Global:Config.Features.ShowNetworkInfo) {
    Show-Network
    Write-Host " "
}
if ($Global:Config.Features.ShowDateTime) {
    Write-Host "Good $($Greeting) $($Global:Config.Settings.Name), it is $LongDate."
    Write-Host ""
}

if ($Global:Config.Features.ShowMOTD) {
    Show-MOTD
}

# Profile Load time information for logging / debugging
$ProfileLoadTime.Stop()
if ($Global:Config.Settings.Debug) {
    Write-Host "`nProfile loaded in $($ProfileLoadTime.Elapsed.TotalMilliseconds.ToString('N0')) ms" -ForegroundColor Green
}
Write-ProfileLog -Level INFO -Message "Profile loaded in $($ProfileLoadTime.Elapsed.TotalMilliseconds.ToString('N0')) ms"