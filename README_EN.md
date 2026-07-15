# Claude Code / Codex / Hermes / CC Switch Installer Collector

A selectable installer for Windows, macOS, Linux, Kali, and WSL. It installs Claude Code, OpenAI Codex CLI, Nous Research Hermes Agent, and CC Switch from their official sources.

## Highlights

- Interactive overall progress with stable line output in CI or redirected terminals.
- Five stages per component: prepare, download, record local SHA-256, install, and verify.
- UTF-8 logs under `~/.ai-cli-installer/logs/` by default.
- Bash downloads use retries, timeouts, and partial-file continuation.
- Component failures are isolated; the final process exits non-zero if any selected item failed.
- No bundled proxy, shared account, token, API key, or region bypass.

A locally calculated SHA-256 is recorded for troubleshooting. It is not presented as upstream signature verification unless the upstream project publishes a trusted checksum.

## Interactive install

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

macOS / Linux / Kali / WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash
```

## Direct selection

```bash
./install.sh --install codex,hermes
./install.sh --install all --no-progress --log-file ~/ai-cli-install.log
```

```powershell
.\install.ps1 -Install codex,hermes
.\install.ps1 -Install all -NoProgress -LogFile "$HOME\ai-cli-install.log"
```

Supported names: `claude,codex,hermes,cc-switch,all`.

## Output controls

| Purpose | Bash | PowerShell |
|---|---|---|
| Disable dynamic progress | `--no-progress` | `-NoProgress` |
| Quiet mode | `--quiet` | `-Quiet` |
| Custom log | `--log-file PATH` | `-LogFile PATH` |
| Debug diagnostics | `--debug` | `-DebugInstaller` |
| Audit only | `--dry-run` | `-DryRun` |

## Validation

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
bash tests/container_matrix.sh
```

GitHub Actions validates Ubuntu, macOS, Windows PowerShell 5.1, and a real `kalilinux/kali-rolling` container.
