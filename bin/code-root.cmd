@echo off
rem Wrapper so that cmd-based callers (e.g. yazi openers) can run code-root.ps1
pwsh -NoProfile -File "%~dp0code-root.ps1" %*
