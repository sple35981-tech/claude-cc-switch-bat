# Installer Progress and Diagnostics Design

## Goal

Upgrade the four-tool installer so users can see meaningful progress, detailed stages, elapsed time, download activity, log location, and actionable failure details on Windows, macOS, Linux, Kali, and WSL without adding dependencies.

## User Experience

The installer has two output modes:

- Interactive terminal: colored status symbols and a single-line overall progress bar updated in place.
- Non-interactive terminal, redirected output, CI, or `--no-progress`: stable line-oriented output with no control sequences.

Each selected component moves through `准备`, `下载`, `安装`, and `验证`. The overall progress is based on completed component stages, not fake time estimates. Native downloader progress remains visible in interactive mode; quiet machine-readable output is available with `--quiet`.

## Logging

Every non-dry-run invocation writes a UTF-8 log. The default path is under the user's temporary/log directory and is printed at startup and in the summary. `--log-file PATH` / `-LogFile PATH` overrides it. Logs contain timestamps, commands with secrets redacted, component status, elapsed seconds, and the final summary. No API keys, authorization headers, proxy credentials, or account data may be logged.

## Failure Behavior

A component failure does not stop later components. The summary lists succeeded, skipped, and failed components, plus the failing stage and exit code. The process returns non-zero when any selected component fails. Download metadata functions must keep machine-returned values on stdout and diagnostics on stderr/logs.

## Compatibility

- Bash 3.2+; no associative arrays, GNU-only `find`, or external UI dependencies.
- Windows PowerShell 5.1+ and PowerShell 7+; UTF-8 BOM retained.
- Existing selection, proxy, skip, dry-run, and non-interactive parameters remain compatible.
- `--no-progress`, `--quiet`, and `--log-file` are added on Bash; `-NoProgress`, `-Quiet`, and `-LogFile` on PowerShell.
- Dry-run does not create package files or invoke installers; it may create an explicit log only when requested.

## Validation

- Unit/static tests for progress calculations, log redaction, options, official sources, and regression cases.
- Executable sandbox tests with fake `curl`, `apt`, `dnf`, `rpm`, `brew`, `ditto`, `unzip`, and installers.
- Platform matrix: Kali/Debian x64 DEB, Fedora/RPM x64, Arch/AppImage x64, macOS arm64, non-TTY, download failure, component failure continuation, and URL-log contamination.
- GitHub Actions: Ubuntu and macOS execute Bash tests/dry-runs; Windows PowerShell 5.1 parses and executes all-component dry-run.
