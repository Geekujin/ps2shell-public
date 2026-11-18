<#
.SYNOPSIS
    Bitwarden CLI secret helpers for PS2Shell.

.DESCRIPTION
    Resolves "SECRET:<Name>" references in profile_config.json from your Bitwarden vault.

    - The vault is only unlocked the first time a secret is requested (not at profile load).
    - The master password is read as a SecureString and passed to bw via a short-lived
      environment variable, never as a command-line argument.
    - The session key lives only in this module's memory. It is never written to disk or
      left in $env:BW_SESSION, so child processes don't inherit it.
    - Retrieved secrets are cached as SecureStrings until Lock-PS2Vault (or shell exit).

    Requires a 'Bitwarden' section in profile_config.json (see Bitwarden.Secrets).
#>

$script:BwSession = $null
$script:Cache     = @{}


# === [PRIVATE HELPERS] === #

function Write-VaultLog {
    param([string]$Message, [string]$Level = 'INFO')
    # Reuse the profile's logger if it's loaded. Never pass secret values to this.
    if (Get-Command Write-ProfileLog -ErrorAction SilentlyContinue) {
        Write-ProfileLog -Level $Level -Message "PS2Bitwarden: $Message"
    }
}

function Get-BwConfig {
    $BwConfig = $Global:Config.Bitwarden
    if (-not $BwConfig) {
        throw "No 'Bitwarden' section found in profile_config.json."
    }
    $BwConfig
}

function Get-BwCliPath {
    $CliPath = (Get-BwConfig).CliPath
    if ([string]::IsNullOrWhiteSpace($CliPath)) { $CliPath = 'bw' }

    if (-not (Get-Command $CliPath -ErrorAction SilentlyContinue)) {
        throw "Bitwarden CLI '$CliPath' not found. Install it with: winget install Bitwarden.CLI"
    }
    $CliPath
}

function Test-CanPrompt {
    if (-not [Environment]::UserInteractive) { return $false }
    -not ([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-noni' })
}

function ConvertTo-PlainText {
    param([securestring]$Secure)
    $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try     { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr) }
}

function Invoke-Bw {
    # Runs bw with the session key available for this one call only
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $CliPath = Get-BwCliPath
    $PreviousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8   # So non-ASCII secrets aren't mangled in 5.1

    if ($script:BwSession) { $env:BW_SESSION = $script:BwSession }
    try {
        $Output = & $CliPath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "bw $($Arguments[0]) failed (exit code $LASTEXITCODE)."
        }
        $Output -join "`n"
    }
    finally {
        Remove-Item Env:\BW_SESSION -ErrorAction SilentlyContinue
        [Console]::OutputEncoding = $PreviousEncoding
    }
}

function Get-SecretReference {
    # Walks the config and returns every "SECRET:<Name>" value with its setting path
    param($Node, [string]$Path = '')

    if ($Node -is [string]) {
        if ($Node -match '^SECRET:(.+)$') {
            [PSCustomObject]@{ Setting = $Path; Secret = $Matches[1] }
        }
        return
    }

    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($Property in $Node.PSObject.Properties) {
            $ChildPath = if ($Path) { "$Path.$($Property.Name)" } else { $Property.Name }
            Get-SecretReference -Node $Property.Value -Path $ChildPath
        }
        return
    }

    if ($Node -is [System.Collections.IEnumerable]) {
        $Index = 0
        foreach ($Child in $Node) {
            Get-SecretReference -Node $Child -Path "$Path[$Index]"
            $Index++
        }
    }
}


# === [PUBLIC FUNCTIONS] === #

function Unlock-PS2Vault {
    <#
    .SYNOPSIS
        Unlocks the Bitwarden vault for this PowerShell session.
    .DESCRIPTION
        Prompts for your master password (masked) if the vault is locked. Called automatically
        by Get-PS2Secret, so you rarely need to run it yourself.
    #>
    [CmdletBinding()]
    param()

    $Status = (Invoke-Bw status | ConvertFrom-Json).status

    if ($Status -eq 'unlocked') { return }

    if ($Status -eq 'unauthenticated') {
        throw "Bitwarden CLI is not logged in. Run 'bw login' once in a terminal first."
    }

    if (-not (Test-CanPrompt)) {
        throw "Bitwarden vault is locked and this session can't prompt for the master password."
    }

    $Secure = Read-Host -Prompt 'Bitwarden master password' -AsSecureString
    $Bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        $env:PS2_BW_UNLOCK = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
        $script:BwSession  = Invoke-Bw unlock --passwordenv PS2_BW_UNLOCK --raw --nointeraction
    }
    catch {
        Write-VaultLog -Level WARN -Message 'Vault unlock failed.'
        throw 'Bitwarden unlock failed (wrong master password?).'
    }
    finally {
        Remove-Item Env:\PS2_BW_UNLOCK -ErrorAction SilentlyContinue
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
        $Secure.Dispose()
    }

    Write-VaultLog -Message 'Vault unlocked.'

    if ((Get-BwConfig).SyncOnUnlock) {
        $null = Invoke-Bw sync --quiet
    }
}

function Lock-PS2Vault {
    <#
    .SYNOPSIS
        Locks the Bitwarden vault and clears all cached secrets from this session.
    #>
    [CmdletBinding()]
    param()

    try {
        foreach ($Secure in $script:Cache.Values) { $Secure.Dispose() }
        $script:Cache.Clear()
        if ($script:BwSession) {
            $null = Invoke-Bw lock
            Write-VaultLog -Message 'Vault locked.'
        }
    }
    finally {
        $script:BwSession = $null
    }
}

function Get-PS2Secret {
    <#
    .SYNOPSIS
        Gets a secret from Bitwarden by its name in profile_config.json.
    .DESCRIPTION
        Accepts either the bare name ("GitHubToken") or the config reference
        ("SECRET:GitHubToken"), so you can pass config values straight in:
            Get-PS2Secret $Config.KnowBe4.ReportingAPI
        Returns a SecureString unless -AsPlainText is given.
    .PARAMETER Name
        Secret name, as listed under Bitwarden.Secrets in the config.
    .PARAMETER AsPlainText
        Return a plain string. Only use at the point an API needs it.
    #>
    [CmdletBinding()]
    [OutputType([securestring], [string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [switch]$AsPlainText
    )

    $Name  = $Name -replace '^SECRET:', ''
    $Entry = (Get-BwConfig).Secrets.$Name

    if (-not $Entry -or [string]::IsNullOrWhiteSpace($Entry.ItemId)) {
        throw "Secret '$Name' has no ItemId under Bitwarden.Secrets in profile_config.json."
    }

    $Field = if ($Entry.Field) { $Entry.Field } else { 'password' }
    if ($Field -notin 'password', 'username', 'notes', 'totp') {
        throw "Secret '$Name' has invalid Field '$Field' (use password, username, notes or totp, or set CustomField)."
    }

    # TOTP codes change every 30 seconds, so never cache them
    $Cacheable = $Field -ne 'totp' -or $Entry.CustomField

    if ($Cacheable -and $script:Cache.ContainsKey($Name)) {
        $Secure = $script:Cache[$Name]
    }
    else {
        Unlock-PS2Vault

        if ($Entry.CustomField) {
            $Item  = Invoke-Bw get item $Entry.ItemId --nointeraction | ConvertFrom-Json
            $Value = ($Item.fields | Where-Object { $_.name -eq $Entry.CustomField } | Select-Object -First 1).value
            $Item  = $null
        }
        else {
            $Value = Invoke-Bw get $Field $Entry.ItemId --nointeraction
        }

        if ([string]::IsNullOrEmpty($Value)) {
            throw "Secret '$Name' is empty or the field wasn't found in Bitwarden item $($Entry.ItemId)."
        }

        $Secure = ConvertTo-SecureString -String $Value -AsPlainText -Force
        $Value  = $null

        if ($Cacheable) { $script:Cache[$Name] = $Secure }
        Write-VaultLog -Level DEBUG -Message "Retrieved secret '$Name'."
    }

    if ($AsPlainText) { ConvertTo-PlainText $Secure } else { $Secure }
}

function Get-PS2Credential {
    <#
    .SYNOPSIS
        Builds a PSCredential from a user name / client ID and a Bitwarden secret.
    .EXAMPLE
        Get-PS2Credential -UserName $Config.DVSA.ClientID -Secret $Config.DVSA.ClientSecret
    #>
    [CmdletBinding()]
    [OutputType([pscredential])]
    param(
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$Secret
    )

    New-Object System.Management.Automation.PSCredential($UserName, (Get-PS2Secret -Name $Secret))
}

function Find-PS2VaultItem {
    <#
    .SYNOPSIS
        Searches your vault and returns item names and IDs, for filling in Bitwarden.Secrets.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Search)

    Unlock-PS2Vault

    # Assign first: in Windows PowerShell 5.1, ConvertFrom-Json emits a JSON array as a single
    # object, so piping it straight into Select-Object gives one blank row. Piping the variable
    # sends the items one at a time.
    $Items = Invoke-Bw list items --search $Search --nointeraction | ConvertFrom-Json

    if (-not $Items) {
        Write-Warning "No vault items match '$Search'. If the item is new, run 'bw sync' or set SyncOnUnlock to true."
        return
    }

    $Items | Select-Object name, id, @{ N = 'username'; E = { $_.login.username } }
}

function Test-PS2SecretConfig {
    <#
    .SYNOPSIS
        Checks that every SECRET: reference in the config maps to a Bitwarden item.
    .PARAMETER Online
        Also fetch each secret from the vault to prove it resolves (values aren't shown).
    #>
    [CmdletBinding()]
    param([switch]$Online)

    $Secrets = (Get-BwConfig).Secrets

    foreach ($Ref in (Get-SecretReference -Node $Global:Config)) {
        $Entry  = $Secrets.($Ref.Secret)
        $Status = if (-not $Entry -or [string]::IsNullOrWhiteSpace($Entry.ItemId)) { 'NOT MAPPED' } else { 'Mapped' }

        if ($Online -and $Status -eq 'Mapped') {
            try {
                $null   = Get-PS2Secret -Name $Ref.Secret
                $Status = 'OK'
            }
            catch {
                $Status = "ERROR: $($_.Exception.Message)"
            }
        }

        [PSCustomObject]@{ Setting = $Ref.Setting; Secret = $Ref.Secret; Status = $Status }
    }
}


# === [MODULE LIFECYCLE] === #

# Lock the vault when the shell exits via 'exit' (closing the window with X may not fire this)
$script:ExitSubscription = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Lock-PS2Vault }

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Lock-PS2Vault
    Get-EventSubscriber |
        Where-Object { $_.Action -and $_.Action.Id -eq $script:ExitSubscription.Id } |
        ForEach-Object { Unregister-Event -SubscriptionId $_.SubscriptionId }
}

Export-ModuleMember -Function Unlock-PS2Vault, Lock-PS2Vault, Get-PS2Secret, Get-PS2Credential, Find-PS2VaultItem, Test-PS2SecretConfig
