#Requires -Version 5.1
<#
.SYNOPSIS
    Port WezTerm aesthetics to Windows Terminal in one command.

.DESCRIPTION
    Patches Windows Terminal settings.json with the Catppuccin Mocha color
    scheme, JetBrainsMono Nerd Font Mono, and WezTerm-style cursor / padding.
    Optionally installs oh-my-posh and a Nerd Font, and wires an idempotent
    init block into the PowerShell $PROFILE.

    All edits are non-destructive:
      - settings.json is backed up to settings.backup.<timestamp>.json.
      - Existing schemes / defaults keys are preserved unless overwritten.
      - $PROFILE edits live between fenced markers and can be re-run safely.

.PARAMETER Scheme
    Color scheme name to apply. Default: "Catppuccin Mocha".

.PARAMETER Font
    Font family. Default: "JetBrainsMono Nerd Font Mono".

.PARAMETER FontSize
    Font size in points. Default: 12.

.PARAMETER FontWeight
    Font weight string (normal, medium, bold, ...). Default: "medium".

.PARAMETER CursorShape
    Cursor shape. Default: "filledBox" (WezTerm BlinkingBlock equivalent).

.PARAMETER Padding
    Cell padding, "top/bottom" or "left, top, right, bottom". Default: "10, 7.5".

.PARAMETER Backdrop
    Optional background image path. When supplied, sets backgroundImage and
    backgroundImageOpacity on the default profile.

.PARAMETER BackdropOpacity
    Background image opacity (0.0 transparent .. 1.0 opaque). Default: 0.30.

.PARAMETER InstallOhMyPosh
    Install oh-my-posh via winget (user scope) if missing.

.PARAMETER InstallFont
    After oh-my-posh is available, run `oh-my-posh font install JetBrainsMono`
    to install the Nerd Font family used by the default font.

.PARAMETER OhMyPoshTheme
    oh-my-posh theme to use in $PROFILE. Default: "catppuccin_mocha".

.PARAMETER SkipProfile
    Do not modify the PowerShell $PROFILE.

.PARAMETER WhatIf
    Show planned changes without writing.

.EXAMPLE
    .\make-profile.ps1
    Apply defaults with no extra installs.

.EXAMPLE
    .\make-profile.ps1 -InstallOhMyPosh -InstallFont
    Full setup: install oh-my-posh + Nerd Font, patch settings, wire $PROFILE.

.EXAMPLE
    .\make-profile.ps1 -Backdrop "$HOME\Pictures\dark-bg.jpg" -BackdropOpacity 0.35
    Add a darkened background image.

.LINK
    https://github.com/cskwork/windows-terminal-wezterm-port
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $Scheme = 'Catppuccin Mocha',
    [string] $Font = 'JetBrainsMono NFM',
    [int]    $FontSize = 12,
    [string] $FontWeight = 'medium',
    [string] $CursorShape = 'filledBox',
    [string] $Padding = '10, 7.5',
    [string] $Backdrop,
    [double] $BackdropOpacity = 0.30,
    [switch] $InstallOhMyPosh,
    [switch] $InstallFont,
    [string] $OhMyPoshTheme = 'catppuccin_mocha',
    [switch] $SkipProfile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Catppuccin Mocha — full 16-color ANSI palette + background / foreground / cursor.
# Source: https://github.com/catppuccin/windows-terminal
$CatppuccinMocha = [ordered]@{
    name                = 'Catppuccin Mocha'
    background          = '#1E1E2E'
    foreground          = '#CDD6F4'
    cursorColor         = '#F5E0DC'
    selectionBackground = '#585B70'
    black               = '#45475A'
    red                 = '#F38BA8'
    green               = '#A6E3A1'
    yellow              = '#F9E2AF'
    blue                = '#89B4FA'
    purple              = '#F5C2E7'
    cyan                = '#94E2D5'
    white               = '#BAC2DE'
    brightBlack         = '#585B70'
    brightRed           = '#F38BA8'
    brightGreen         = '#A6E3A1'
    brightYellow        = '#F9E2AF'
    brightBlue          = '#89B4FA'
    brightPurple        = '#F5C2E7'
    brightCyan          = '#94E2D5'
    brightWhite         = '#A6ADC8'
}

function Resolve-SettingsPath {
    $candidates = @(
        # Microsoft Store stable
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        # Microsoft Store preview
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        # Unpackaged install
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    throw "Windows Terminal settings.json not found. Open Windows Terminal once to create it, then re-run."
}

function Backup-File {
    param([Parameter(Mandatory)][string] $Path)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Split-Path -Parent $Path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    $backup = Join-Path $dir ("{0}.backup.{1}{2}" -f $name, $stamp, $ext)
    Copy-Item -LiteralPath $Path -Destination $backup
    Write-Host "  backup -> $backup" -ForegroundColor DarkGray
    return $backup
}

function ConvertTo-OrderedHashtable {
    # PowerShell 5.1 ConvertFrom-Json returns PSCustomObject; we need a recursive
    # ordered hashtable to mutate cleanly and write back with stable key order.
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $h[$p.Name] = ConvertTo-OrderedHashtable $p.Value
        }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        return @($InputObject | ForEach-Object { ConvertTo-OrderedHashtable $_ })
    }
    return $InputObject
}

function Merge-Scheme {
    param(
        [Parameter(Mandatory)] $Settings,
        [Parameter(Mandatory)] [hashtable] $NewScheme
    )
    if (-not $Settings.Contains('schemes')) { $Settings['schemes'] = @() }
    $existing = @($Settings['schemes'] | Where-Object { $_.name -ne $NewScheme.name })
    $existing += [pscustomobject]$NewScheme
    $Settings['schemes'] = $existing
}

function Merge-Defaults {
    param(
        [Parameter(Mandatory)] $Settings,
        [Parameter(Mandatory)] [hashtable] $Overrides
    )
    if (-not $Settings.Contains('profiles')) { $Settings['profiles'] = [ordered]@{} }
    if (-not $Settings['profiles'].Contains('defaults')) { $Settings['profiles']['defaults'] = [ordered]@{} }
    $defaults = $Settings['profiles']['defaults']
    foreach ($k in $Overrides.Keys) {
        $defaults[$k] = $Overrides[$k]
    }
    $Settings['profiles']['defaults'] = $defaults
}

function Get-EntryField {
    # Read a named field from a settings entry regardless of whether the JSON
    # deserialized into a hashtable, ordered dictionary, or PSCustomObject.
    param($Entry, [string] $Field)
    if ($null -eq $Entry) { return $null }
    if ($Entry -is [hashtable] -or $Entry -is [System.Collections.Specialized.OrderedDictionary]) {
        if ($Entry.Contains($Field)) { return $Entry[$Field] }
        return $null
    }
    $prop = $Entry.PSObject.Properties[$Field]
    if ($prop) { return $prop.Value }
    return $null
}

function Merge-TopLevel {
    param(
        [Parameter(Mandatory)] $Settings,
        [Parameter(Mandatory)] [hashtable] $Overrides
    )
    foreach ($k in $Overrides.Keys) {
        $Settings[$k] = $Overrides[$k]
    }
}

function Merge-Actions {
    # Append our action entries to the global 'actions' array. Dedup by id and
    # by keys so re-running the installer never duplicates and any user binding
    # on the same key is replaced (this is the whole point of the port: own
    # Ctrl+C / Ctrl+V as copy/paste).
    param(
        [Parameter(Mandatory)] $Settings,
        [Parameter(Mandatory)] $NewActions
    )
    if (-not $Settings.Contains('actions')) { $Settings['actions'] = @() }
    $newIds  = @($NewActions | ForEach-Object { Get-EntryField $_ 'id' }   | Where-Object { $_ })
    $newKeys = @($NewActions | ForEach-Object { Get-EntryField $_ 'keys' } | Where-Object { $_ })
    $kept = @($Settings['actions'] | Where-Object {
        $entry = $_
        $entryId   = Get-EntryField $entry 'id'
        $entryKeys = Get-EntryField $entry 'keys'
        -not (($entryId -and ($newIds -contains $entryId)) -or
              ($entryKeys -and ($newKeys -contains $entryKeys)))
    })
    $Settings['actions'] = @($kept + $NewActions)
}

function Install-OhMyPoshIfMissing {
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Host "  oh-my-posh already installed" -ForegroundColor DarkGray
        return
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget not found — install oh-my-posh manually from https://ohmyposh.dev"
        return
    }
    Write-Host "  installing oh-my-posh via winget (user scope) ..." -ForegroundColor Cyan
    & winget install JanDeDobbeleer.OhMyPosh `
        --silent --accept-source-agreements --accept-package-agreements --scope user
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget install failed (exit $LASTEXITCODE). Continuing."
    }
}

function Get-RegisteredFontFamilies {
    # Returns the set of installed font family names from HKCU + HKLM. Family is
    # derived by stripping the " (TrueType)" / weight / style suffix from the
    # registry value name (e.g. "JetBrainsMono NFM Medium (TrueType)" -> "JetBrainsMono NFM").
    $keys = @(
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    $weights = 'Thin|ExtraLight|Light|Regular|Medium|SemiBold|Bold|ExtraBold|Black'
    $styles = 'Italic|Oblique'
    $families = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($k in $keys) {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        $props = (Get-ItemProperty -LiteralPath $k)
        foreach ($n in $props.PSObject.Properties.Name) {
            if ($n -like 'PS*') { continue }
            $fam = $n -replace '\s*\(TrueType\)\s*$', ''
            $fam = $fam -replace "\s+($weights)(\s+($styles))?$", ''
            [void]$families.Add($fam.Trim())
        }
    }
    return $families
}

function Test-FontInstalled {
    param([Parameter(Mandatory)][string] $Family)
    (Get-RegisteredFontFamilies).Contains($Family)
}

function Install-NerdFontIfRequested {
    param([string] $FamilyHint = 'JetBrainsMono')
    $omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $omp) {
        $shim = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\oh-my-posh.exe'
        if (Test-Path -LiteralPath $shim) { $omp = $shim } else {
            Write-Warning "oh-my-posh not found — re-run with -InstallOhMyPosh to install Nerd Font."
            return
        }
    }
    Write-Host "  installing $FamilyHint Nerd Font via oh-my-posh (headless) ..." -ForegroundColor Cyan
    & $omp font install $FamilyHint --headless
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "oh-my-posh font install exited $LASTEXITCODE — check manually."
    }
}

function Update-PowerShellProfile {
    param([string] $ThemeName)
    if (-not (Test-Path -LiteralPath $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
        Write-Host "  created $PROFILE" -ForegroundColor DarkGray
    }
    $content = Get-Content -LiteralPath $PROFILE -Raw -ErrorAction SilentlyContinue
    if (-not $content) { $content = '' }

    $start = '# >>> wezterm-port (oh-my-posh + Catppuccin Mocha) >>>'
    $end = '# <<< wezterm-port <<<'
    # Closing "@ MUST sit at column 0, or the parser treats the here-string
    # as unterminated. Do not indent it.
    $block = @"
$start
# Resolve oh-my-posh themes dir robustly: \$env:POSH_THEMES_PATH is not set by
# the MSIX winget install, so fall back to the exe directory (following the
# WindowsApps symlink if needed).
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    `$themesDir = `$env:POSH_THEMES_PATH
    if (-not `$themesDir -or -not (Test-Path `$themesDir)) {
        `$ompSrc = (Get-Command oh-my-posh).Source
        `$candidates = @((Join-Path (Split-Path `$ompSrc) 'themes'))
        try {
            `$resolved = (Get-Item -LiteralPath `$ompSrc).Target
            if (`$resolved) { `$candidates += (Join-Path (Split-Path `$resolved) 'themes') }
        } catch {}
        `$candidates += (Get-ChildItem 'C:\Program Files\WindowsApps' -Directory -Filter 'ohmyposh.cli_*' -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path `$_.FullName 'themes' })
        `$themesDir = `$candidates | Where-Object { `$_ -and (Test-Path -LiteralPath `$_) } | Select-Object -First 1
    }
    if (`$themesDir) {
        `$ompTheme = Join-Path `$themesDir '$ThemeName.omp.json'
        if (-not (Test-Path `$ompTheme)) {
            `$ompTheme = Join-Path `$themesDir 'jandedobbeleer.omp.json'
        }
        if (Test-Path `$ompTheme) {
            oh-my-posh init pwsh --config `$ompTheme | Invoke-Expression
        } else {
            oh-my-posh init pwsh | Invoke-Expression
        }
    } else {
        oh-my-posh init pwsh | Invoke-Expression
    }
}
$end
"@

    if ($content.Contains($start)) {
        $before = $content.Substring(0, $content.IndexOf($start))
        $afterIdx = $content.IndexOf($end) + $end.Length
        $after = $content.Substring($afterIdx)
        $new = ($before.TrimEnd() + "`r`n`r`n" + $block + "`r`n" + $after.TrimStart())
        Set-Content -LiteralPath $PROFILE -Value $new -NoNewline:$false
        Write-Host "  refreshed wezterm-port block in $PROFILE" -ForegroundColor DarkGray
    }
    else {
        $append = ($content.TrimEnd() + "`r`n`r`n" + $block + "`r`n")
        Set-Content -LiteralPath $PROFILE -Value $append -NoNewline:$false
        Write-Host "  appended wezterm-port block to $PROFILE" -ForegroundColor DarkGray
    }
}

# --- main -------------------------------------------------------------------

Write-Host "windows-terminal-wezterm-port" -ForegroundColor Magenta
$settingsPath = Resolve-SettingsPath
Write-Host "  settings: $settingsPath" -ForegroundColor DarkGray

$raw = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
$settings = ConvertTo-OrderedHashtable (ConvertFrom-Json $raw)

if ($Scheme -eq 'Catppuccin Mocha') {
    Merge-Scheme -Settings $settings -NewScheme $CatppuccinMocha
}

$overrides = [ordered]@{
    colorScheme      = $Scheme
    font             = [ordered]@{
        face   = $Font
        size   = $FontSize
        weight = $FontWeight
    }
    cursorShape      = $CursorShape
    padding          = $Padding
    antialiasingMode = 'cleartype'
    useAcrylic       = $false
}
if ($Backdrop) {
    $overrides['backgroundImage'] = (Resolve-Path -LiteralPath $Backdrop).Path
    $overrides['backgroundImageOpacity'] = $BackdropOpacity
    $overrides['backgroundImageStretchMode'] = 'uniformToFill'
}
Merge-Defaults -Settings $settings -Overrides $overrides

# Copy/paste UX (WezTerm-style):
#   - select-to-copy via copyOnSelect
#   - right-click pastes (or copies if selection exists) by disabling the
#     experimental context menu
#   - Ctrl+C / Ctrl+V keybindings (Windows Terminal's `copy` action is a no-op
#     when no text is selected, so Ctrl+C still passes through to the shell as
#     SIGINT — exactly the smart behavior users expect)
Merge-TopLevel -Settings $settings -Overrides ([ordered]@{
    copyOnSelect                          = $true
    'experimental.rightClickContextMenu'  = $false
})
# Windows Terminal's modern schema splits "action definition" from "keybinding":
#   { "id": "...", "command": ... }        defines the action
#   { "id": "...", "keys": "..." }         binds a key to that id
# If both command and keys live in a single entry, WT silently drops keys on its
# next settings reload — leaving the binding inert. Emit two entries each.
Merge-Actions -Settings $settings -NewActions @(
    [ordered]@{
        id      = 'User.wezterm-port.copy'
        name    = 'Copy (wezterm-port)'
        command = [ordered]@{ action = 'copy'; singleLine = $false }
    },
    [ordered]@{
        id   = 'User.wezterm-port.copy'
        keys = 'ctrl+c'
    },
    [ordered]@{
        id      = 'User.wezterm-port.paste'
        name    = 'Paste (wezterm-port)'
        command = 'paste'
    },
    [ordered]@{
        id   = 'User.wezterm-port.paste'
        keys = 'ctrl+v'
    }
)

$json = ConvertTo-Json $settings -Depth 100

if ($PSCmdlet.ShouldProcess($settingsPath, 'patch Windows Terminal settings')) {
    Backup-File -Path $settingsPath | Out-Null
    Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8
    Write-Host "  patched: scheme '$Scheme' + font '$Font $FontSize' + cursor '$CursorShape'" -ForegroundColor Green
    Write-Host "  copy/paste: select-to-copy + right-click paste + Ctrl+C/Ctrl+V (Ctrl+C still SIGINTs when nothing selected)" -ForegroundColor DarkGray
}

if ($InstallOhMyPosh) { Install-OhMyPoshIfMissing }
if ($InstallFont) { Install-NerdFontIfRequested -FamilyHint 'JetBrainsMono' }

if (-not (Test-FontInstalled $Font)) {
    Write-Warning "Font '$Font' is not registered. Windows Terminal will fall back to a default."
    $jetbrainsFams = (Get-RegisteredFontFamilies) | Where-Object { $_ -like 'JetBrains*' } | Sort-Object -Unique
    if ($jetbrainsFams) {
        Write-Host "  installed JetBrains families:" -ForegroundColor DarkGray
        $jetbrainsFams | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }
        Write-Host "  re-run with: -Font '<one of the above>'" -ForegroundColor DarkGray
    } else {
        Write-Host "  no JetBrains families found. Run again with -InstallFont (and -InstallOhMyPosh if needed)." -ForegroundColor DarkGray
    }
}

if (-not $SkipProfile) {
    if ($PSCmdlet.ShouldProcess($PROFILE, 'add oh-my-posh init')) {
        Update-PowerShellProfile -ThemeName $OhMyPoshTheme
    }
}

Write-Host ""
Write-Host "done. open a new Windows Terminal tab to see the changes." -ForegroundColor Green
Write-Host "  uninstall: .\uninstall.ps1" -ForegroundColor DarkGray
