---
name: windows-terminal-wezterm-port
description: Apply WezTerm aesthetics (Catppuccin Mocha, JetBrainsMono Nerd Font, filled-block cursor, generous padding, oh-my-posh prompt) to Windows Terminal in one command. Windows-only. Triggers on "make PowerShell look like WezTerm", "WezTerm style for Windows Terminal", "Catppuccin Mocha PowerShell", "wezterm port windows", "윈도우 터미널 wezterm 스타일", "파워셸 카푸치노 mocha".
---

# windows-terminal-wezterm-port skill

Windows-only. Brings the WezTerm look — Catppuccin Mocha palette,
JetBrainsMono Nerd Font Mono, filled-block cursor, 10/7.5 padding, and an
`oh-my-posh` prompt — to Windows Terminal by patching its `settings.json`
non-destructively.

## When to use this skill

Triggers:

- User wants Windows Terminal / PowerShell to look like WezTerm.
- User asks for Catppuccin Mocha on Windows Terminal.
- User wants a JetBrains Mono Nerd Font setup on Windows.
- User wants an `oh-my-posh` prompt wired into `$PROFILE`.
- Korean equivalents: "윈도우 터미널 꾸미기", "파워셸 테마", "터미널 색상", "Catppuccin 윈도우".

Skip when:

- User is on macOS or Linux. Point them at
  [cskwork/iterm2-wezterm-port](https://github.com/cskwork/iterm2-wezterm-port)
  or the native `wezterm` skill instead.
- User actually wants to switch *to* WezTerm (use the `wezterm` skill).

## Prerequisites check

Before running, verify:

1. Platform is Windows (`$IsWindows -or $env:OS -eq 'Windows_NT'`).
2. Windows Terminal `settings.json` exists at one of:
   - `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` (Store stable)
   - `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json` (Preview)
   - `%LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json` (unpackaged)
   If absent: ask the user to open Windows Terminal once so it generates the file.
3. PowerShell 5.1+ is available (built into Windows 10/11).
4. Optional: `winget` is on PATH if the user wants
   `oh-my-posh` installed automatically.

## Operating procedure

1. **Clone or update the repo**:
   ```powershell
   git clone https://github.com/cskwork/windows-terminal-wezterm-port
   cd windows-terminal-wezterm-port
   ```

2. **Read the user's current `settings.json`** before running. Confirm whether
   they have existing customizations in `profiles.defaults`, `schemes`, or
   profile-specific overrides. The installer is idempotent and non-destructive
   for the keys it does not touch, but you should still surface what will
   change.

3. **Pick flags** based on what the user already has installed:

   | Situation                                  | Recommended command                              |
   |--------------------------------------------|--------------------------------------------------|
   | First-time setup (nothing installed)       | `.\make-profile.ps1 -InstallOhMyPosh -InstallFont` |
   | Nerd Font already installed                | `.\make-profile.ps1 -InstallOhMyPosh`            |
   | oh-my-posh + Nerd Font already there       | `.\make-profile.ps1`                             |
   | Wants a background image                   | add `-Backdrop "<path>" -BackdropOpacity 0.30`   |
   | Wants only the colors (no prompt change)   | add `-SkipProfile`                               |

4. **Run with `pwsh -ExecutionPolicy Bypass -File`** if execution policy
   blocks the script. The script honors `-WhatIf` for a dry run.

5. **Verify** by:
   - Reading the modified `settings.json` and confirming the
     `Catppuccin Mocha` entry appears in `schemes`.
   - Confirming `profiles.defaults` now contains the expected `colorScheme`,
     `font`, `cursorShape`, `padding` keys.
   - Confirming a `# >>> wezterm-port` fenced block is in `$PROFILE`.
   - Asking the user to open a new Windows Terminal tab (no restart needed).

## Rollback

```powershell
.\uninstall.ps1                      # remove added keys + $PROFILE block
.\uninstall.ps1 -RestoreLatestBackup # restore the latest settings.backup.*.json byte-for-byte
```

The backup files are named `settings.backup.<yyyyMMdd-HHmmss>.json` next to
the live `settings.json`.

## Known gotchas

- **The Microsoft Store package path uses `8wekyb3d8bbwe`** (no `c`). A common
  typo is `8wekyb3d8bbcwe`; if you copy a path from another doc, double-check.
- **`useAcrylic: false` is forced** so the Catppuccin background renders
  cleanly. If the user explicitly wants acrylic, override per-profile in
  `profiles.list` (defaults are inherited, not enforced).
- **Per-profile overrides win** over `profiles.defaults`. If a single shell
  still looks wrong, check whether that shell's profile has explicit `font`
  or `colorScheme` keys in `profiles.list`.
- **`oh-my-posh font install JetBrainsMono` is interactive** in some
  versions; if it prompts for a font variant, choose `Mono` for terminal use.
- **PowerShell ISE does not honor the WT settings**. The script targets
  Windows Terminal + pwsh / PowerShell, not ISE.

## Customization knobs

All parameters of `make-profile.ps1`:

| Parameter           | Default                              | Notes                                              |
|---------------------|--------------------------------------|----------------------------------------------------|
| `-Scheme`           | `Catppuccin Mocha`                   | Only Catppuccin Mocha is bundled; can target any   |
|                     |                                      | existing scheme name in `settings.json`            |
| `-Font`             | `JetBrainsMono Nerd Font Mono`       | Must already be installed (or use `-InstallFont`)  |
| `-FontSize`         | `12`                                 | Points                                             |
| `-FontWeight`       | `medium`                             | `normal`, `medium`, `bold`, etc.                   |
| `-CursorShape`      | `filledBox`                          | WezTerm `BlinkingBlock` equivalent                 |
| `-Padding`          | `10, 7.5`                            | "all" or "left, top, right, bottom"                |
| `-Backdrop`         | unset                                | File path; sets `backgroundImage`                  |
| `-BackdropOpacity`  | `0.30`                               | 0 transparent .. 1 opaque                          |
| `-InstallOhMyPosh`  | off                                  | `winget install JanDeDobbeleer.OhMyPosh`           |
| `-InstallFont`      | off                                  | `oh-my-posh font install JetBrainsMono`            |
| `-OhMyPoshTheme`    | `catppuccin_mocha`                   | Falls back to `jandedobbeleer` if missing          |
| `-SkipProfile`      | off                                  | Skip the `$PROFILE` block                          |

## Reference

Repo: <https://github.com/cskwork/windows-terminal-wezterm-port>
Sibling (macOS): <https://github.com/cskwork/iterm2-wezterm-port>
