# dotfiles (Windows)

Personal Windows configuration for Neovim, PowerShell, Oh My Posh, WezTerm, VSCode, and Yazi.

## Requirements

- Windows 10/11
- PowerShell 7 (recommended)
- Neovim (0.8+ recommended)
- Git

## Install

1. Clone the repository.

```powershell
git clone https://github.com/kazuhisa-okamoto/dotfiles.git
cd dotfiles
```

2. Run `install.ps1` as administrator (symbolic links require elevation), adjusting the execution policy as needed.

```powershell
# Preview only: prints every action without touching the filesystem
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun

# Apply
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

## How it works

`install.ps1` creates a symbolic link at each configuration location pointing back to the corresponding file in this repository, so edits in the repo take effect immediately.

Existing files at a target path are renamed to `<name>.bak.<yyyyMMdd-HHmmss>` before the link is created. Existing symbolic links are removed without a backup and recreated, so re-running the script is safe.

## Configuration paths

Every source-to-target mapping is defined in the `$links` array near the top of `install.ps1`. Edit that array to add, remove, or relocate a configuration file.
