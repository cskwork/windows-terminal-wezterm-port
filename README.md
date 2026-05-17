# windows-terminal-wezterm-port

Port WezTerm aesthetics to Windows Terminal in one command. Catppuccin Mocha
palette, JetBrainsMono Nerd Font, optional darkened background image,
filled-block cursor, generous padding — applied to the global profile
`defaults` block so every shell (PowerShell, pwsh, WSL, Git Bash, cmd) gets
the same look without restarting Windows Terminal.

This is the Windows counterpart to
[cskwork/iterm2-wezterm-port](https://github.com/cskwork/iterm2-wezterm-port).

## What it ports from WezTerm

| WezTerm setting                          | Windows Terminal equivalent applied      |
| ---------------------------------------- | ---------------------------------------- |
| `color_scheme = 'Catppuccin Mocha'`      | Full 16-color ANSI + bg / fg / cursor    |
| `font = JetBrainsMono Nerd Font Medium`  | `JetBrainsMono NFM 12 medium` (Nerd Fonts v3 short name) |
| `default_cursor_style = BlinkingBlock`   | `cursorShape: filledBox`                 |
| `backdrops/*` random rotation            | Single static image (configurable)       |
| Window padding (top 10, bottom 7.5)      | `padding: "10, 7.5"`                     |
| Prompt with git / path / glyphs          | `oh-my-posh` with `catppuccin_mocha`     |

What does **not** port (Windows Terminal does not support it natively):

- Random backdrop rotation per launch — Windows Terminal takes one static image.
- `LEADER+b/Shift+B` runtime backdrop cycling.
- WezTerm's WebGPU 120fps rendering and FreeType tuning.
- Per-pane background images (Windows Terminal only supports per-profile).

## Requirements

- Windows 10 or 11
- [Windows Terminal](https://aka.ms/terminal) (Store or unpackaged) — open it
  at least once so `settings.json` exists
- PowerShell 5.1+ (built in) or PowerShell 7+
- Optional: [winget](https://learn.microsoft.com/windows/package-manager/winget/)
  for the `-InstallOhMyPosh` flag

## Install

```powershell
git clone https://github.com/cskwork/windows-terminal-wezterm-port
cd windows-terminal-wezterm-port

# Catppuccin Mocha + JetBrainsMono Nerd Font + oh-my-posh prompt
pwsh -ExecutionPolicy Bypass -File .\make-profile.ps1 -InstallOhMyPosh -InstallFont
```

Open a new Windows Terminal tab. The scheme loads immediately because
`settings.json` is watched for changes — no restart required.

If you already have a Nerd Font installed and `oh-my-posh` on PATH, just run:

```powershell
.\make-profile.ps1
```

## Customize

```powershell
.\make-profile.ps1 -?
```

Common tweaks:

```powershell
# Bigger font
.\make-profile.ps1 -FontSize 14

# Different Nerd Font (must be installed; use v3 short family name)
.\make-profile.ps1 -Font "CaskaydiaCove NFM" -FontSize 13

# Darkened background image
.\make-profile.ps1 -Backdrop "$HOME\Pictures\dark-bg.jpg" -BackdropOpacity 0.30

# Image more visible
.\make-profile.ps1 -Backdrop "$HOME\Pictures\dark-bg.jpg" -BackdropOpacity 0.55

# Skip the $PROFILE oh-my-posh wiring (only patch Windows Terminal)
.\make-profile.ps1 -SkipProfile

# Different oh-my-posh theme
.\make-profile.ps1 -OhMyPoshTheme jandedobbeleer
```

Re-run with any combination of flags — `settings.json` and `$PROFILE` are
idempotent. The previous values are overwritten, not duplicated.

## How it works

1. Locates `settings.json` (Microsoft Store stable, Preview, or unpackaged).
2. Writes a timestamped backup next to it
   (`settings.backup.<yyyyMMdd-HHmmss>.json`).
3. Inserts the Catppuccin Mocha scheme into the `schemes` array (replaces if
   already present, never duplicates).
4. Sets `colorScheme`, `font`, `cursorShape`, `padding`, `useAcrylic`,
   `antialiasingMode` (and optional background image) inside `profiles.defaults`
   so every profile inherits the look.
5. Writes the JSON back. Windows Terminal picks it up live.
6. If `-InstallOhMyPosh` is set, runs
   `winget install JanDeDobbeleer.OhMyPosh --scope user`.
7. If `-InstallFont` is set, runs `oh-my-posh font install JetBrainsMono`.
8. Appends an idempotent fenced block to `$PROFILE` that wires `oh-my-posh init`
   on shell start.

Existing profiles, schemes, keybindings, and customizations are left
untouched. Anything you set inside an individual profile in `profiles.list`
overrides the defaults.

## Troubleshooting

**"다음 글꼴을 찾을 수 없습니다. JetBrainsMono Nerd Font Mono" / "Font not found"**

Nerd Fonts v3 registers families with short names like `JetBrainsMono NFM`
(NFM = Nerd Font Mono), not the long pre-v3 `JetBrainsMono Nerd Font Mono`.
The installer defaults to the v3 short name. If you copied the long name
from an older guide, change `-Font` to one of:

| Variant            | v3 short name             |
|--------------------|---------------------------|
| Mono, ligatures    | `JetBrainsMono NFM`       |
| Mono, no-ligature  | `JetBrainsMonoNL NFM`     |
| Variable width     | `JetBrainsMono NF`        |
| Proportional       | `JetBrainsMono NFP`       |

After running the installer, it prints the registered JetBrains family list
if your `-Font` value does not match anything. Pick one from that list.

**Font files are on disk but not registered**

If `oh-my-posh font install` was interrupted previously, the `.ttf` files may
sit in `%LOCALAPPDATA%\Microsoft\Windows\Fonts\` without registry entries.
Re-run:

```powershell
.\make-profile.ps1 -InstallFont
```

The script invokes `oh-my-posh font install JetBrainsMono --headless` which
both copies and registers the family.

**`$env:POSH_THEMES_PATH` is null when PROFILE runs**

oh-my-posh's MSIX (winget) install does not always set the
`POSH_THEMES_PATH` user environment variable, so `Join-Path` errors out on
the next shell start. The installer-emitted `$PROFILE` block already handles
this: it resolves the themes directory from the `oh-my-posh.exe` location
(following the WindowsApps symlink) before touching `--config`, and falls
back to the default theme if no themes directory is found.

If your existing PROFILE was written by an older version of this installer,
re-run `.\make-profile.ps1` — the fenced block between the markers is
replaced in place, not duplicated.

**Script blocked by execution policy**

```powershell
pwsh -ExecutionPolicy Bypass -File .\make-profile.ps1
```

This bypasses the policy for one invocation without changing your global
setting.

## Uninstall

```powershell
# Remove the scheme + defaults keys this script added, plus the $PROFILE block
.\uninstall.ps1

# Or restore the most recent timestamped backup byte-for-byte
.\uninstall.ps1 -RestoreLatestBackup
```

Optionally remove oh-my-posh:

```powershell
winget uninstall JanDeDobbeleer.OhMyPosh
```

## Use as an oh-my-claudecode skill

If you use [oh-my-claudecode](https://github.com/cskwork/oh-my-claudecode),
this repo doubles as a skill. Drop `SKILL.md` (or symlink the repo) into
`~/.claude/skills/windows-terminal-wezterm-port/` and Claude Code will offer
to run it when you say things like "make my PowerShell look like WezTerm" or
"apply Catppuccin Mocha to Windows Terminal."

## License

MIT. See [LICENSE](LICENSE).
