@echo off
rem Wrapper so that cmd-based callers (e.g. yazi openers) can run vs.ps1
pwsh -NoProfile -File "%~dp0vs.ps1" %*
