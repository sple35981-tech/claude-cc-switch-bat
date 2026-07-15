# AI CLI Installer Collector

A selectable installer for Claude Code, OpenAI Codex CLI, Nous Research Hermes Agent, and CC Switch on Windows, macOS, Linux, Kali, and WSL.

## Quick install

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

macOS/Linux/Kali/WSL:

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

## Detailed progress and logs

Interactive terminals show an overall progress bar. CI and no-TTY sessions automatically use stable line-oriented steps. Every component follows prepare, download, install, and verify phases. Failures are isolated and summarized at the end.

Useful options:

```text
--quiet / -Quiet
--no-progress / -NoProgress
--log-file PATH / -LogFile PATH
--debug (Bash only)
--keep-temp (Bash only)
```

Default logs are stored under `~/.local/state/ai-cli-installer/logs/` on Unix-like systems and `%LOCALAPPDATA%\ai-cli-installer\logs\` on Windows.

## Validation

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
bash tests/container_matrix.sh
```

The simulated container matrix does not install real software. GitHub Actions validates Ubuntu, macOS, and Windows.

Only official project sources are used. The installer does not provide shared accounts, API keys, default mirrors, or regional/account restriction bypasses.
