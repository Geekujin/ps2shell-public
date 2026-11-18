# PS2Shell

A configurable PowerShell profile for Windows. It gives you a custom prompt, searchable command history, Bitwarden-backed secrets, and a folder structure to store your scripts, modules and other related files. Everything is driven by one JSON config file.

```
 ███████████   █████████   ████████          █████████  █████               ████  ████ 
░░███░░░░░███ ███░░░░░███ ███░░░░███        ███░░░░░███░░███               ░░███ ░░███ 
 ░███    ░███░███    ░░░ ░░░    ░███       ░███    ░░░  ░███████    ██████  ░███  ░███ 
 ░██████████ ░░█████████    ███████  ██████░░█████████  ░███░░███  ███░░███ ░███  ░███ 
 ░███░░░░░░   ░░░░░░░░███  ███░░░░  ░░░░░░  ░░░░░░░░███ ░███ ░███ ░███████  ░███  ░███ 
 ░███         ███    ░███ ███      █        ███    ░███ ░███ ░███ ░███░░░   ░███  ░███ 
 █████       ░░█████████ ░██████████       ░░█████████  ████ █████░░██████  █████ █████
░░░░░         ░░░░░░░░░  ░░░░░░░░░░         ░░░░░░░░░  ░░░░ ░░░░░  ░░░░░░  ░░░░░ ░░░░░ 

┍──────────────────────────────────────────────────────────┑
│ HOST: MY-LAPTOP | LAN: 192.168.1.20 | VPN: Not Connected │
└──────────────────────────────────────────────────────────┘

Good morning Alex, it is Wednesday the 18th of November 2026.

Message of the Day

"Any sufficiently advanced technology is indistinguishable from magic."
 - Arthur C. Clarke

[09:14:02] Alex@MY-LAPTOP:~\Projects$
```

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Repository layout](#repository-layout)
- [Installation](#installation)
- [Configuration reference](#configuration-reference)
- [Using the profile](#using-the-profile)
- [Command history](#command-history)
- [Secrets with Bitwarden (PS2Bitwarden)](#secrets-with-bitwarden-ps2bitwarden)
- [Included scripts](#included-scripts)
- [Logging and debugging](#logging-and-debugging)
- [Extending PS2Shell](#extending-ps2shell)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)

---

## Features

- **Start screen**: a colour-themed ASCII banner, a HOST/LAN/VPN network box, a greeting based on the time of day, and a random message of the day. You can turn each part on or off.
- **Custom prompt**: `[HH:mm:ss] Name@COMPUTER:~\path$`, with your home folder shortened to `~`.
- **Persistent command history**: every command is saved to a JSON Lines file with its timestamp and whether it succeeded or failed. Search it by date, date range, text or errors only.
- **Credential redaction**: commands that look like they contain passwords, tokens or API keys are saved as `[redacted]` in both the PS2Shell history and PSReadLine's history.
- **Bitwarden secrets**: put `SECRET:<Name>` references in your config instead of real secrets. They are resolved from your vault the first time you need them, and only held in memory as `SecureString`s.
- **Config-driven setup**: script and module folders are added to `PATH` and `PSModulePath`. Modules, dot-sourced scripts and aliases are all loaded from the config.
- **Safe to reload**: `reload` runs the profile again without adding duplicate `PATH` entries.
- **Built-in help**: `pshelp` lists every profile function and its synopsis.

## Requirements

| Requirement | Notes |
|---|---|
| Windows | The network box, `Get-Volumes`, `Get-WifiNetworks` and the prompt's computer name rely on Windows APIs and tools. |
| PowerShell 7+ (recommended) or Windows PowerShell 5.1 | The code is written to work on both. |
| A terminal with UTF-8 and a Unicode font | Needed for the banner, box-drawing characters and emoji. Windows Terminal with Cascadia Code or a Nerd Font works well. |
| [Bitwarden CLI](https://bitwarden.com/help/cli/) (`bw`) | Optional. Only needed for the secrets module. `winget install Bitwarden.CLI` |

## Repository layout

```
ps2shell/
├── ps2shell-profile.ps1              # The profile itself
├── .config/
│   ├── profile_config.example.json   # Template config (copy this)
│   ├── profile_config.json           # Your live config (git-ignored, you create it)
│   └── motd.txt                      # Messages of the day, one per line
├── modules/
│   └── PS2Bitwarden/
│       └── PS2Bitwarden.psm1         # Bitwarden secrets module
├── scripts/                          # Added to PATH, so scripts run by name
│   ├── Get-Volumes.ps1               # List fixed storage volumes
│   ├── Get-WifiNetworks.ps1          # Extract WIFI SSID and password information
│   ├── List-Scripts.ps1              # Lists all scripts in the scripts folder, along with its .SYNOPSIS if present
│   ├── Show-Colors.ps1               # Prints each colour combination supported by terminal
│   └── Show-Emoji.ps1                # Displays emoji in the terminal. Just because
├── logs/                             # Profile log and command history
└── reports/                          # Optional folder to place script outputs
```

## Installation

### 1. Get the files

Clone the repository, or download it as a ZIP and extract it, to a permanent location such as `C:\Tools\ps2shell`:

```powershell
git clone https://github.com/<owner>/<repository>.git C:\Tools\ps2shell
```

### 2. Allow local scripts to run

If you haven't already done this:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Files downloaded as a ZIP may be marked as coming from the internet. Unblock them:

```powershell
Get-ChildItem C:\Tools\ps2shell -Recurse | Unblock-File
```

### 3. Create the config and log folder

```powershell
cd C:\Tools\ps2shell
Copy-Item .config\profile_config.example.json .config\profile_config.json
New-Item -ItemType Directory -Path logs, reports -Force
```

> **Important:** create the `logs` folder. The profile log and command history silently do nothing if the folder doesn't exist.

### 4. Edit `profile_config.json`

At a minimum, replace every `C:\\Path\\To\\ps2shell\\` with your real path, and set `Name` and `Home`. See the [Configuration reference](#configuration-reference) for the full list.

In JSON, each backslash must be doubled (`C:\\Tools\\ps2shell\\`).

### 5. Hook it into your PowerShell profile

PS2Shell doesn't replace your `$PROFILE`. Your profile dot-sources it instead. Open your profile:

```powershell
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }
notepad $PROFILE
```

Add this line:

```powershell
. 'C:\Tools\ps2shell\ps2shell-profile.ps1'
```

PowerShell 7 and Windows PowerShell 5.1 use different `$PROFILE` files. Add the line to each one you use.

### 6. Start a new shell

Open a new terminal tab. You should see the banner and start screen. If you see `[!] Profile initialization aborted`, see [Troubleshooting](#troubleshooting).

---

## Configuration reference

The profile always reads its config from `.config\profile_config.json`, next to `ps2shell-profile.ps1`. After loading, the whole config is available in your session as `$Config` (also `$Global:Config`), so your own scripts can read from it.

### `Settings`

| Key | Purpose |
|---|---|
| `ConfigName` | A label for this config, such as `Work` or `Home`. Informational only. |
| `Name` | Your display name, used in the prompt and the greeting. |
| `WindowTitle` | Text for the terminal window or tab title. |
| `debug` | `true` turns on step timings at startup and `DEBUG` entries in the log. |
| `PS2ShellRoot` | Root of the PS2Shell folder. |
| `ScriptRoot` | Added to `PATH`, so the scripts in it can be run by name. Also the base folder for relative `DotSourceFiles` entries. |
| `ModuleRoot` | Added to `PSModulePath`, so modules in it can be imported by name. |
| `SettingsFolder` | Where `motd.txt` is read from. and the `profile_config.json` lives. |
| `LogFolder` | Where `ps2_profile.log` and `history.jsonl` are written. Falls back to `<profile folder>\logs`. |
| `ProfilePath` | Full path to `ps2shell-profile.ps1`. Used by `Reload-Profile`. |
| `ExeFolder` | An optional extra folder of executables to add to `PATH`. |
| `ReportsFolder` | An output folder for your own scripts. The profile doesn't use it. |
| `Home` | Your home folder. The prompt shows this part of the path as `~`. **Don't put a trailing backslash on it**: `C:\\Users\\alex` gives `~\Projects`, but `C:\\Users\\alex\\` gives `~Projects`. |

### `Features`

All values are `true` or `false`.

| Key | Effect |
|---|---|
| `ShowBanner` | Shows the ASCII banner, coloured with the `Standard` art theme. |
| `ShowNetworkInfo` | Shows the HOST / LAN / VPN box. |
| `ShowDateTime` | Shows "Good *morning* *Name*, it is *Wednesday the 18th of November 2026*." |
| `ShowMOTD` | Shows a random line from `motd.txt`. |
| `UpdateProfile` | Reserved for the planned self-updater. **Keep this `false`** (see [Known limitations](#known-limitations)). |

### `Modules`

An array of module names to import at startup. Modules in `ModuleRoot` can be listed by name alone.

```json
"Modules": [ "PS2Bitwarden", "ImportExcel" ]
```

If a module fails to load, you get a warning and the profile keeps going.

### `DotSourceFiles`

An array of scripts to dot-source at startup, which is useful for files of extra functions. Relative paths are resolved against `ScriptRoot`.

```json
"DotSourceFiles": [ "MyFunctions.ps1", "C:\\Shared\\TeamFunctions.ps1" ]
```

### `Aliases`

Pairs of alias name and target command, created in the global scope.

```json
"Aliases": {
    "reload": "Reload-Profile",
    "pshelp": "Get-PS2ShellHelp",
    "grep":   "Select-String"
}
```

`Profile-Help` is always available as an alias for `Get-PS2ShellHelp`.

### `ArtThemes`

Each theme maps characters to [console colour names](#show-colorsps1). The startup banner uses `Standard`. Characters not in the map are drawn in `Gray`.

```json
"ArtThemes": {
    "Standard": { "░": "DarkRed", "█": "White" },
    "Matrix":   { "░": "DarkGreen", "█": "Green" }
}
```

You can use any theme with your own ASCII art:

```powershell
Write-ColorMappedArt -Text (Get-Content .\art.txt -Raw -Encoding UTF8) -Theme Matrix
```

### `NetworkLocations`

Maps network (connection profile) names to a friendly location and coordinates. The profile loads these into `$LocationMap`, a hashtable keyed by network name, for your own scripts to use, for example in location-aware weather or reporting scripts:

```powershell
$Net = (Get-NetworkInfo -IncludeNetworkName).NetworkName
$LocationMap[$Net]   # @{ Latitude = 12.34; Longitude = -1.23; Name = 'Home' }
```

### `Users`

Free-form account names, such as admin and standard UPNs, for your scripts to use (`$Config.Users.EntraAdmin`). The profile itself doesn't use them.

### `Bitwarden`

Settings for the PS2Bitwarden module. See [Secrets with Bitwarden](#secrets-with-bitwarden-ps2bitwarden).

### `ProfileUpdater`

The GitHub repository that your profile is published to. `Publish-PS2ShellRepo.ps1` uses it.

```json
"ProfileUpdater": {
    "Owner": "your-github-user",
    "Repository": "ps2shell",
    "Branch": "main"
}
```

---

## Using the profile

### Profile commands

| Command | Alias | Description |
|---|---|---|
| `Get-PS2ShellHelp [Name]` | `pshelp`, `Profile-Help` | With no name, lists every profile function and its synopsis. With a name, shows the detailed help for that function. |
| `Reload-Profile` | `reload` | Clears the screen and loads the profile again. Use this after you edit the config or profile. |
| `Get-CommandHistory` | | Searches the persistent history. See [Command history](#command-history). |
| `Get-NetworkInfo [-IncludeNetworkName]` | | Returns the host name, LAN IP and VPN IP as an object. `-IncludeNetworkName` also looks up the connected network's name, which is slower. |
| `Show-Network` | | Draws the HOST / LAN / VPN box. |
| `Show-MOTD` | | Shows a random message of the day. |
| `Write-ColorMappedArt` | | Prints text with each character coloured by an art theme. |
| `Get-DateWithOrdinal` | | Returns a date such as `Wednesday the 18th of November 2026`. |
| `Get-TimeOfDay` | | Returns `morning`, `afternoon`, `evening` or `night`. |
| `Add-PathEntry -Variable PATH -Entry <dir>` | | Adds a folder to a PATH-style variable for this session, only if it isn't already listed. |

### Network box

`Show-Network` picks the first active IPv4 adapter that isn't a loopback, link-local, Hyper-V or virtual adapter, and shows it as **LAN**. An adapter whose description matches `VPN`, `WireGuard`, `Fortinet`, `TAP` or `TUN` is shown as **VPN**. If your VPN client uses a different adapter name, add it to `$VpnPattern` in `Get-NetworkInfo`.

### Message of the day

Edit `.config\motd.txt` and put one message on each line. Blank lines are ignored. Lines in the form `"Quote" - Source` are shown as a quote with the source on its own line in a different colour. Any other line is shown as it is.

```
"Talk is cheap. Show me the code." - Linus Torvalds
Remember to lock your screen.
```

---

## Command history

The prompt appends every command you run to `logs\history.jsonl`, one JSON object per line:

```json
{"Timestamp":"2026-11-18T09:14:02.1234567+00:00","HistoryId":12,"Status":"ERROR","Command":"Get-Item C:\\nope","Error":"Cannot find path 'C:\\nope' because it does not exist."}
```

Unlike PowerShell's built-in `Get-History`, this file is kept across sessions and also records whether each command succeeded.

### Searching it

```powershell
Get-CommandHistory                               # Last 20 commands
Get-CommandHistory -Last 100                     # Last 100 commands
Get-CommandHistory -Date 2026-11-17              # Everything from one day
Get-CommandHistory -From '2026-11-01' -To '2026-11-07 18:00'
Get-CommandHistory -Search 'Invoke-RestMethod'   # Plain-text match on the command or error
Get-CommandHistory -Last 200 -ErrorsOnly         # Only failed commands
Get-CommandHistory -Search robocopy -Raw         # Only the command text, for copying
```

Calls to `Get-CommandHistory` and `h` aren't recorded, so the history doesn't fill up with history searches.

### Redaction

A command is saved as `[redacted: possible credential]`, and kept out of PSReadLine's own history file, if it matches any of:

`password`, `passwd`, `secret`, `token`, `api_key` / `api-key` / `apikey`, `bearer`, `-AsPlainText`, `ConvertTo-SecureString`, `BW_SESSION`, `bw unlock`, `bw login`, `bw get`

The match isn't case-sensitive. To change the list, edit `$script:HistoryRedactPattern` near the top of `ps2shell-profile.ps1`.

> Redaction matches keywords, so it can't catch everything. A secret pasted on its own, with none of the keywords around it, will still be logged. Treat `logs\` as sensitive.

---

## Secrets with Bitwarden (PS2Bitwarden)

PS2Bitwarden lets you keep secrets out of `profile_config.json`. The config contains only *references* (`SECRET:<Name>`) and Bitwarden item IDs. The real values stay in your vault.

### How it protects secrets

- The vault is **only unlocked the first time you ask for a secret**, not when the profile loads, so opening a shell stays fast and doesn't prompt you.
- Your master password is read as a masked `SecureString` and passed to `bw` through a short-lived environment variable, never as a command-line argument.
- The `bw` session key is kept only in the module's memory. It's set in `BW_SESSION` for the length of each `bw` call and removed straight afterwards, so child processes don't inherit it.
- Secrets you retrieve are cached as `SecureString`s until you run `Lock-PS2Vault` or exit the shell. TOTP codes are never cached.
- Non-interactive sessions, such as scheduled tasks or `pwsh -NonInteractive`, never hang on a password prompt. They fail with an error instead.

### Setup

1. Install the CLI and log in once:

   ```powershell
   winget install Bitwarden.CLI
   bw login
   ```

   Self-hosted or EU users should first run `bw config server <url>`.

2. Find the IDs of the items you need:

   ```powershell
   Find-PS2VaultItem github
   # name                id                                    username
   # ----                --                                    --------
   # GitHub PS2Shell PAT 2f6c1c9e-....-....-....-............  alex
   ```

3. Add each one under `Bitwarden.Secrets` with a short name of your choice:

   ```json
   "Bitwarden": {
       "CliPath": "bw",
       "SyncOnUnlock": true,
       "Secrets": {
           "GitHubPS2Shell": { "ItemId": "2f6c1c9e-..." },
           "ServiceUser":    { "ItemId": "8a1d...", "Field": "username" },
           "MfaCode":        { "ItemId": "8a1d...", "Field": "totp" },
           "ReportingKey":   { "ItemId": "c03e...", "CustomField": "API Key" }
       }
   }
   ```

   | Key | Meaning |
   |---|---|
   | `CliPath` | The `bw` command or a full path to `bw.exe`. Defaults to `bw`. |
   | `SyncOnUnlock` | Runs `bw sync` after unlocking, so items added recently are found. |
   | `ItemId` | The Bitwarden item GUID. Required. |
   | `Field` | `password` (the default), `username`, `notes` or `totp`. |
   | `CustomField` | The name of a custom field on the item. Used instead of `Field`. |

4. Refer to the secrets anywhere else in your config:

   ```json
   "Reporting": {
       "ApiUrl": "https://api.example.com",
       "ApiKey": "SECRET:ReportingKey"
   }
   ```

5. Check that every reference is mapped:

   ```powershell
   Test-PS2SecretConfig            # Checks the config only
   Test-PS2SecretConfig -Online    # Also fetches each secret from the vault (values aren't shown)
   ```

### Using secrets in scripts

```powershell
# Get a SecureString (the default)
$Key = Get-PS2Secret ReportingKey

# Config references can be passed straight in
$Key = Get-PS2Secret $Config.Reporting.ApiKey

# Get plain text only at the point an API needs it
$Headers = @{ Authorization = "Bearer $(Get-PS2Secret GitHubPS2Shell -AsPlainText)" }

# Build a PSCredential from a user name and a secret
$Cred = Get-PS2Credential -UserName $Config.Users.EntraAdmin -Secret 'EntraAdminPassword'

# Clear the cached secrets and lock the vault when you've finished
Lock-PS2Vault
```

### Module commands

| Command | Description |
|---|---|
| `Get-PS2Secret <Name> [-AsPlainText]` | Returns a secret, unlocking the vault first if needed. |
| `Get-PS2Credential -UserName <u> -Secret <Name>` | Returns a `PSCredential`. |
| `Find-PS2VaultItem <search>` | Searches the vault and lists item names, IDs and user names. |
| `Test-PS2SecretConfig [-Online]` | Checks every `SECRET:` reference in the config. |
| `Unlock-PS2Vault` | Unlocks the vault. Other commands do this automatically when needed. |
| `Lock-PS2Vault` | Clears cached secrets and locks the vault. This also runs when you leave the shell with `exit`, though closing the window may not trigger it. |

---

## Included scripts

`ScriptRoot` is on your `PATH`, so you can run these by name from any folder.

### `List-Scripts.ps1`

Lists every `.ps1` file in the scripts folder with the text of its `.SYNOPSIS`. Add a comment-based help block to your own scripts and they'll show up here too.

```powershell
List-Scripts
```

### `Show-Colors.ps1`

Prints a 16×16 chart of every foreground and background combination of `ConsoleColor`, with a key. Use it to choose colours for `ArtThemes` or `Write-Host`.

```powershell
Show-Colors
```

### `Show-Emoji.ps1`

Prints ranges of Unicode emoji, so you can check what your terminal font can display.

```powershell
Show-Emoji                 # Lists the available types
Show-Emoji -Type Faces     # Faces, People, Animals, Food, Travel, Objects, Symbols, Sports, Supplemental
Show-Emoji -Type All
```

### `Get-Volumes.ps1`

Lists the logical drives with their label, type, file system, size and free space in GB.

```powershell
Get-Volumes | Format-Table
```

### `Get-WifiNetworks.ps1`

Lists every saved Wi-Fi profile on the machine with its password **in plain text**, using `netsh`. Some profiles may need an elevated shell. Be careful where you run this and who can see your screen.

```powershell
Get-WifiNetworks
```

---

## Logging and debugging

- **Profile log**: `logs\ps2_profile.log` records each profile load, how long it took, and any module, dot-source or config errors, each with a timestamp and level (`DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`).
- **Debug mode**: set `"debug": true` in `Settings` to print a timer after each startup step, such as configuration, modules, aliases and banner, and to write `DEBUG` entries to the log. Use it to find out what's making your shell slow to start.

```
Profile Step Timer: Configuration loading              12 ms
Profile Step Timer: Secrets module loaded              48 ms
Profile Step Timer: Module Loading Complete           210 ms
...
Profile loaded in 312 ms
```

Your own scripts can write to the same log with `Write-ProfileLog -Level WARN -Message "..."`.

---

## Extending PS2Shell

- **Add a script**: put a `.ps1` file with a `.SYNOPSIS` block in `scripts\`. It can be run by name straight away, and `List-Scripts` will show it.
- **Add a function library**: put it in `scripts\` and list it in `DotSourceFiles`.
- **Add a module**: create `modules\<Name>\<Name>.psm1` and add `<Name>` to `Modules`.
- **Read settings in your scripts**: use `$Config.<Section>.<Key>`, and `Get-PS2Secret $Config.<Section>.<Key>` for secrets.
- **Add a shortcut**: add an entry under `Aliases`.

Run `reload` to pick up your changes.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `[!] Profile initialization aborted: Config file not found` | `.config\profile_config.json` doesn't exist next to `ps2shell-profile.ps1`. Copy it from the example file. |
| `Failed to parse JSON` | The config isn't valid JSON. Common causes are single backslashes in paths (use `\\`) and trailing commas. Windows PowerShell 5.1 is stricter than PowerShell 7 about trailing commas, so check with `Get-Content .config\profile_config.json -Raw \| ConvertFrom-Json`. |
| No history or log file | The `LogFolder` doesn't exist. Create it. |
| Banner or box shows `?` or broken characters | The terminal font doesn't include those characters. Switch to Windows Terminal with Cascadia Code or a Nerd Font. Make sure the config is saved as UTF-8. |
| `running scripts is disabled on this system` | Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, and use `Unblock-File` on downloaded files. |
| The prompt shows `~Documents` with no slash | Remove the trailing `\\` from `Settings.Home`. |
| VPN shows "Not Connected" while connected | Your VPN adapter's description doesn't match the VPN pattern. Extend `$VpnPattern` in `Get-NetworkInfo`. |
| `Bitwarden CLI is not logged in` | Run `bw login` once. |
| `Find-PS2VaultItem` doesn't find a new item | Run `bw sync`, or set `SyncOnUnlock` to `true`. |
| An error about `Update-Profile` at startup | Set `Features.UpdateProfile` and `Features.UpdateConfig` to `false`. |

---

## Known limitations

- **No self-updater yet.** The `UpdateProfile` feature flag, and the `update` alias in the example config, refer to `Update-Profile`. This function isn't included yet, so keep the flag `false` and remove the `update` alias until it is.
- **Windows only.** The profile may load on PowerShell 7 for Linux or macOS, but the network box, computer name and several scripts depend on Windows.
- **One banner theme.** The startup banner always uses the `Standard` art theme. Other themes are only available through `Write-ColorMappedArt` or editing the profile.
