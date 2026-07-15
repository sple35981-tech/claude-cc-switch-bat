# Claude Code / Codex / Hermes / CC Switch 一键安装集合器

面向 Windows、macOS、Linux、Kali 和 WSL 的四合一安装器。运行一个脚本后，可以自己选择安装：

- **Claude Code**：Anthropic 官方原生安装器。
- **OpenAI Codex CLI**：OpenAI 官方安装器。
- **Hermes Agent**：Nous Research 官方安装器。
- **CC Switch**：[`farion1231/cc-switch`](https://github.com/farion1231/cc-switch) 官方 Releases。

默认不内置第三方中转站、共享账号、API Key 或下载镜像。针对中国用户常见网络情况，提供当前进程代理、GitHub 下载前缀、超时重试、网络诊断和 dry-run。

## 支持平台

| 平台 | 支持情况 |
|---|---|
| Windows 10/11 | PowerShell 5.1+，x64/ARM64 |
| macOS 12+ | Intel / Apple Silicon |
| Debian 系 | Ubuntu、Debian、Kali、Linux Mint、Pop!_OS 等 |
| RPM 系 | Fedora、RHEL、Rocky、CentOS、openSUSE 等 |
| 其他 Linux | x86_64/ARM64，CC Switch 回退 AppImage |
| WSL1/WSL2 | Claude、Codex、Hermes；CC Switch GUI 建议安装到 Windows 主机 |

## 最简单的交互式安装

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

脚本会显示：

```text
1) Claude Code
2) OpenAI Codex CLI
3) Nous Research Hermes Agent
4) CC Switch
5) 全部安装
0) 退出
```

可以输入 `1,3,4` 一次选择多个。

### macOS / Linux / Kali / WSL

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash
```

Bash 脚本通过 `/dev/tty` 显示交互菜单，因此使用 `curl | bash` 时仍然可以输入选择。

## 不显示菜单，直接指定组件

### 安装 Codex 和 Hermes

Windows：

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Install codex,hermes
```

macOS / Linux / Kali / WSL：

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash -s -- --install codex,hermes
```

### 安装全部四项

```powershell
.\install.ps1 -Install all
```

```bash
./install.sh --install all
```

支持的组件名：

```text
claude,codex,hermes,cc-switch,all
```

## 非交互环境

CI、无人值守服务器或没有终端时，建议始终显式使用 `--install` / `-Install`。

为了兼容旧版脚本，无交互终端且没有指定组件时，默认安装：

```text
Claude Code + CC Switch
```

## 中国网络环境

### 使用本地代理

```powershell
.\install.ps1 -Install all -Proxy http://127.0.0.1:7890
```

```bash
./install.sh --install all --proxy http://127.0.0.1:7890
```

代理只对当前安装进程生效，不会永久修改系统设置。

### GitHub Release 下载前缀

该参数只影响 CC Switch 的 GitHub Release 下载：

```powershell
.\install.ps1 -Install cc-switch -GitHubProxy https://your-trusted-proxy.example/
```

```bash
./install.sh --install cc-switch --github-proxy https://your-trusted-proxy.example/
```

代理服务能够看到或修改下载内容，请只使用自己信任的服务。默认不开启任何镜像。

## 常用参数

| 功能 | Bash | PowerShell |
|---|---|---|
| 选择组件 | `--install codex,hermes` | `-Install codex,hermes` |
| 安装全部 | `--install all` | `-Install all` |
| Claude 稳定通道 | `--channel stable` | `-Channel stable` |
| Claude 最新通道 | `--channel latest` | `-Channel latest` |
| 当前进程代理 | `--proxy URL` | `-Proxy URL` |
| GitHub 下载前缀 | `--github-proxy URL` | `-GitHubProxy URL` |
| 跳过 Claude | `--skip-claude` | `-SkipClaude` |
| 跳过 Codex | `--skip-codex` | `-SkipCodex` |
| 跳过 Hermes | `--skip-hermes` | `-SkipHermes` |
| 跳过 CC Switch | `--skip-cc-switch` | `-SkipCCSwitch` |
| 只预览 | `--dry-run` | `-DryRun` |
| 禁用菜单 | `--non-interactive` | `-NonInteractive` |
| 跳过网络预检 | `--skip-network-check` | `-SkipNetworkCheck` |

## Dry-run 审计

```powershell
.\install.ps1 -Install all -DryRun -NonInteractive -SkipNetworkCheck
```

```bash
./install.sh --install all --dry-run --non-interactive --skip-network-check
```

Dry-run 会显示官方来源和计划执行的命令，但不会下载或修改系统。

## 安装失败处理

四个组件分别在独立错误边界内安装。某一项失败后，集合器会继续尝试剩余项目，最后输出：

```text
成功: ...
跳过: ...
失败: ...
```

只要有一个已选择组件失败，脚本最终返回非零退出码，方便 CI 判断结果。

## 安装后命令

```bash
claude --version
codex --version
hermes --version
```

启动：

```bash
claude
codex
hermes
```

Hermes 首次配置：

```bash
hermes setup
hermes model
hermes doctor
```

CC Switch 可从 Windows 开始菜单、macOS Launchpad 或 Linux 应用菜单启动。Linux AppImage 回退路径：

```text
~/.local/bin/cc-switch.AppImage
```

## WSL 建议

Claude Code、Codex 和 Hermes 应安装在项目代码所在环境。CC Switch 是桌面 GUI，WSL 用户通常更适合在 Windows 主机安装 CC Switch，再根据自己的配置目录管理 CLI 工具。

## 安全说明

- Claude Code：`https://claude.ai/install.sh` / `install.ps1`。
- Codex CLI：`https://chatgpt.com/codex/install.sh` / `install.ps1`。
- Hermes Agent：`https://hermes-agent.nousresearch.com/install.sh` / `install.ps1`。
- CC Switch：`farion1231/cc-switch` 官方 GitHub Releases。
- 不收集账号、Token、API Key、机器标识或使用数据。
- 不绕过任何产品的地区、账号、订阅或服务条款限制。
- 执行远程脚本前，可以先下载并审计源代码。

## 开发与测试

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
./install.sh --install all --dry-run --non-interactive --skip-network-check
```

GitHub Actions 会在 Ubuntu、macOS 和 Windows 上测试选择逻辑、官方来源、Bash 语法和 PowerShell 语法。

## 许可证

MIT。四个上游项目分别遵循各自许可证、服务条款和地区可用性规则。
