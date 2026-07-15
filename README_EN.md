# Claude Code + CC Switch Cross-Platform Installer

One-command installers for Windows, macOS, Linux, and WSL:

- **Claude Code** is installed from Anthropic's official native installer.
- **CC Switch** is installed from the official releases of [`farion1231/cc-switch`](https://github.com/farion1231/cc-switch).

The scripts add proxy options, retries, network diagnostics, dynamic release selection, and dry-run support. They do not bypass regional availability, account restrictions, or service terms, and they do not embed API keys, shared accounts, or third-party relay services.

## Quick start

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

macOS / Linux / WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash
```

## Proxy examples

```powershell
.\install.ps1 -Proxy http://127.0.0.1:7890
```

```bash
./install.sh --proxy http://127.0.0.1:7890
```

A user-supplied GitHub download prefix is also supported with `-GitHubProxy` or `--github-proxy`. No mirror is enabled by default; only use a service you trust.

## Dry run

```powershell
.\install.ps1 -DryRun -SkipNetworkCheck
```

```bash
./install.sh --dry-run --skip-network-check
```

## Verification

```bash
claude --version
claude doctor
```

## Tests

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
```

Licensed under MIT. Claude Code and CC Switch remain subject to their own licenses, terms, and availability rules.
