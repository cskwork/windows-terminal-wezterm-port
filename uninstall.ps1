#Requires -Version 5.1
<#
.SYNOPSIS
    Revert windows-terminal-wezterm-port changes.

.DESCRIPTION
    Removes the "Catppuccin Mocha" scheme this installer added, clears the
    defaults keys it set, and removes the oh-my-posh init block from $PROFILE.

    The original settings.json is also available as
    settings.backup.<timestamp>.json next to the live file — restore that file
    if you want a fully byte-for-byte rollback.

.PARAMETER RestoreLatestBackup
    Restore the most recent settings.backup.*.json instead of editing in place.

.PARAMETER SkipProfile
    Do not touch $PROFILE.

.EXAMPLE
    .\uninstall.ps1

.EXAMPLE
    .\uninstall.ps1 -RestoreLatestBackup
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $RestoreLatestBackup,
    [switch] $SkipProfile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-SettingsPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { return $p } }
    throw "Windows Terminal settings.json not found."
}

function ConvertTo-OrderedHashtable {
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

$settingsPath = Resolve-SettingsPath
Write-Host "windows-terminal-wezterm-port uninstall" -ForegroundColor Magenta
Write-Host "  settings: $settingsPath" -ForegroundColor DarkGray

if ($RestoreLatestBackup) {
    $dir = Split-Path -Parent $settingsPath
    $latest = Get-ChildItem -LiteralPath $dir -Filter 'settings.backup.*.json' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "No settings.backup.*.json found in $dir" }
    if ($PSCmdlet.ShouldProcess($settingsPath, "restore from $($latest.Name)")) {
        Copy-Item -LiteralPath $latest.FullName -Destination $settingsPath -Force
        Write-Host "  restored from $($latest.Name)" -ForegroundColor Green
    }
}
else {
    $settings = ConvertTo-OrderedHashtable (ConvertFrom-Json (Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8))

    if ($settings.Contains('schemes')) {
        $settings['schemes'] = @($settings['schemes'] | Where-Object { $_.name -ne 'Catppuccin Mocha' })
    }
    $keysToClear = 'colorScheme', 'font', 'cursorShape', 'padding', 'antialiasingMode', 'useAcrylic',
                   'backgroundImage', 'backgroundImageOpacity', 'backgroundImageStretchMode'
    if ($settings.Contains('profiles') -and $settings['profiles'].Contains('defaults')) {
        $defaults = $settings['profiles']['defaults']
        foreach ($k in $keysToClear) { if ($defaults.Contains($k)) { $defaults.Remove($k) } }
        $settings['profiles']['defaults'] = $defaults
    }

    # Top-level copy/paste UX flags this installer adds.
    foreach ($k in 'copyOnSelect', 'experimental.rightClickContextMenu') {
        if ($settings.Contains($k)) { $settings.Remove($k) }
    }

    # Only remove action entries we own (id-prefixed). Never touch user-defined
    # ctrl+c/ctrl+v bindings that existed before.
    if ($settings.Contains('actions')) {
        $settings['actions'] = @($settings['actions'] | Where-Object {
            $entry = $_
            $id = $null
            if ($entry -is [hashtable] -or $entry -is [System.Collections.Specialized.OrderedDictionary]) {
                if ($entry.Contains('id')) { $id = $entry['id'] }
            } else {
                $prop = $entry.PSObject.Properties['id']
                if ($prop) { $id = $prop.Value }
            }
            -not ($id -and $id.StartsWith('User.wezterm-port.'))
        })
    }

    if ($PSCmdlet.ShouldProcess($settingsPath, 'remove wezterm-port keys')) {
        Set-Content -LiteralPath $settingsPath -Value (ConvertTo-Json $settings -Depth 100) -Encoding UTF8
        Write-Host "  removed scheme + defaults + copy/paste overrides" -ForegroundColor Green
    }
}

if (-not $SkipProfile -and (Test-Path -LiteralPath $PROFILE)) {
    $content = Get-Content -LiteralPath $PROFILE -Raw
    $start = '# >>> wezterm-port (oh-my-posh + Catppuccin Mocha) >>>'
    $end = '# <<< wezterm-port <<<'
    if ($content.Contains($start) -and $content.Contains($end)) {
        $before = $content.Substring(0, $content.IndexOf($start)).TrimEnd()
        $after = $content.Substring($content.IndexOf($end) + $end.Length).TrimStart()
        $new = if ($before -and $after) { $before + "`r`n`r`n" + $after + "`r`n" }
               elseif ($before) { $before + "`r`n" }
               else { $after }
        if ($PSCmdlet.ShouldProcess($PROFILE, 'remove wezterm-port block')) {
            Set-Content -LiteralPath $PROFILE -Value $new
            Write-Host "  removed wezterm-port block from $PROFILE" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  no wezterm-port block found in $PROFILE" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "done. open a new Windows Terminal tab to confirm." -ForegroundColor Green
