# dotfiles (Windows)

Personal Windows configuration for Neovim, PowerShell, Oh My Posh, WezTerm, VSCode, and Yazi.

## Requirements

- Windows 10/11
- VS Code (installed separately, e.g. `winget install Microsoft.VisualStudioCode`)

Everything else (scoop, Git, PowerShell 7, Neovim, WezTerm, ...) is installed by `bootstrap.ps1`.

## Install

1. Install scoop and Git from Windows PowerShell as a normal user, then clone the repository.

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
irm get.scoop.sh | iex
scoop install git
git clone https://github.com/kazuhisa-okamoto/dotfiles.git
cd dotfiles
```

2. Run `bootstrap.ps1` as a normal user (scoop refuses to run its installer as administrator). It installs scoop itself if it is missing, the scoop buckets and apps in `packages/scoop-buckets.txt` and `packages/scoop-apps.txt`, and the packages in `packages/pipx.txt` and `packages/npm.txt`. Anything already installed is skipped.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

3. Open a new terminal so the new PATH takes effect, then run `install.ps1` as administrator (symbolic links require elevation).

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

## VS Code extensions

`install.ps1` also installs every extension listed in `vscode/extensions.txt` (one extension ID per line) that is not installed yet, using the `code` CLI. Extensions already installed are skipped, and extensions not in the list are left untouched. With `-DryRun`, it only prints the extensions it would install.

To refresh the list from the current PC:

```powershell
code --list-extensions > vscode\extensions.txt
```

## Yazi plugins

`install.ps1` runs `ya pkg install` after linking `yazi/package.toml`, which installs the plugins listed there.

## Package lists

`bootstrap.ps1` reads these lists. Blank lines and lines starting with `#` are ignored.

| File | Format |
|---|---|
| `packages/scoop-buckets.txt` | `<name> [<git url>]`; the url can be omitted for buckets scoop knows by name |
| `packages/scoop-apps.txt` | `<bucket>/<app>` |
| `packages/pipx.txt` | package name |
| `packages/npm.txt` | package name (installed with `npm install -g`) |
| `packages/tablacus-addons.txt` | Tablacus Explorer add-on ID, for add-ons not bundled with the app |

Tablacus add-ons are downloaded from https://tablacus.github.io/TablacusExplorerAddons/ into the app's `addons` folder. scoop keeps only the app's `config` folder across updates, so run `bootstrap.ps1` again after `scoop update tablacus-explorer` to put the add-ons back.

Besides the lists, `bootstrap.ps1` adds a `te64` shim for Tablacus Explorer (its scoop manifest only creates `te64.exe.exe`) and sets the user environment variable `CLAUDE_CODE_GIT_BASH_PATH` to scoop's Git Bash, so Claude Code does not depend on a Git installed under `C:\Program Files`.
