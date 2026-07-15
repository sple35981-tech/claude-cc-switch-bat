# Claude Code / Codex / Hermes / CC Switch Installer Collector

A dependency-free four-tool installer for Windows, macOS, Linux, Kali, and WSL. It installs from the official Claude Code, OpenAI Codex CLI, Nous Research Hermes Agent, and `farion1231/cc-switch` sources.

## Detailed progress

Every selected component reports four truthful stages:

```text
prepare -> download -> install -> verify
```

Interactive terminals receive an overall progress bar. CI, redirected output, non-TTY sessions, and `--no-progress` automatically receive stable line-oriented output. The final summary includes successes, failures, the failed stage, exit code, elapsed time, and the detailed log path.

## One-line install

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

macOS / Linux / Kali / WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash
```

Install selected tools:

```bash
./install.sh --install codex,hermes
```

```powershell
.\install.ps1 -Install codex,hermes
```

Valid component names are `claude,codex,hermes,cc-switch,all`.

## Progress and log controls

```bash
./install.sh --install all --no-progress
./install.sh --install all --quiet
./install.sh --install cc-switch --log-file ./install.log
```

```powershell
.\install.ps1 -Install all -NoProgress
.\install.ps1 -Install all -Quiet
.\install.ps1 -Install cc-switch -LogFile .\install.log
```

Non-dry-run executions create a UTF-8 log by default. Proxy user information, authorization values, and common API-key assignments are redacted before logging.

## Proxy use

```bash
./install.sh --install all --proxy http://127.0.0.1:7890
```

```powershell
.\install.ps1 -Install all -Proxy http://127.0.0.1:7890
```

A user-supplied GitHub download prefix is supported through `--github-proxy` / `-GitHubProxy`. No third-party mirror is enabled by default.

## Dry-run

```bash
./install.sh --install all --dry-run --skip-network-check --no-progress
```

```powershell
.\install.ps1 -Install all -DryRun -SkipNetworkCheck -NoProgress
```

## Exit status

- `0`: all selected component workflows succeeded; a post-install PATH warning is non-fatal.
- `1`: at least one component failed, while later components were still processed.
- `2`: invalid arguments, unsupported platform, or initialization failure.

Automation should inspect the exit code, failed-stage summary, and log file.

## Validation

```bash
python3 -m unittest discover -s tests -v
python3 tests/container_matrix.py
bash -n install.sh
```

The sandbox matrix covers Kali/DEB, Fedora/RPM, Arch/AppImage, macOS ARM64, non-TTY behavior, failure continuation, redaction, and the GitHub release URL contamination regression. GitHub Actions validates Ubuntu, macOS, and Windows PowerShell 5.1.
