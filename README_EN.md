# Claude Code / Codex / Hermes / CC Switch Installer Collector

A selectable installer for Windows, macOS, Linux, Kali, and WSL. It installs any combination of:

- Claude Code from Anthropic's official installer.
- OpenAI Codex CLI from OpenAI's official installer.
- Hermes Agent from Nous Research's official installer.
- CC Switch from the official `farion1231/cc-switch` GitHub releases.

## Interactive installation

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

macOS / Linux / WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash
```

Select multiple entries such as `1,3,4`, or choose `5` for all tools.

## Explicit selection

```powershell
.\install.ps1 -Install codex,hermes
.\install.ps1 -Install all
```

```bash
./install.sh --install codex,hermes
./install.sh --install all
```

Valid names are `claude`, `codex`, `hermes`, `cc-switch`, and `all`.

In a non-interactive environment with no explicit selection, the legacy default remains Claude Code plus CC Switch. For CI and servers, explicitly pass `--install` or `-Install`.

## Proxy examples

```powershell
.\install.ps1 -Install all -Proxy http://127.0.0.1:7890
```

```bash
./install.sh --install all --proxy http://127.0.0.1:7890
```

A custom GitHub download prefix only affects CC Switch releases and is never enabled by default.

## Dry run

```powershell
.\install.ps1 -Install all -DryRun -NonInteractive -SkipNetworkCheck
```

```bash
./install.sh --install all --dry-run --non-interactive --skip-network-check
```

Each component is isolated: one failure does not prevent the remaining selected components from being attempted. The installer prints a final success/failure summary and returns a non-zero status if any selected component failed.

The scripts do not embed API keys, shared accounts, unofficial relays, or default mirrors, and they do not bypass regional availability or service terms.
