# Claude Code / Codex / Hermes / CC Switch 一键安装集合器

面向 Windows、macOS、Linux、Kali 和 WSL 的四合一安装器。运行一个脚本后，可以选择安装：

- **Claude Code**：Anthropic 官方安装器。
- **OpenAI Codex CLI**：OpenAI 官方安装器。
- **Hermes Agent**：Nous Research 官方安装器。
- **CC Switch**：`farion1231/cc-switch` 官方 GitHub Releases。

脚本只使用官方安装源，不内置第三方中转站、共享账号、API Key 或默认下载镜像，也不会绕过地区、账号或服务条款限制。

## 新版安装体验

- 总体进度：真实终端显示动态进度条，CI、SSH 重定向和 `--no-progress` 自动使用稳定的逐行进度。
- 分阶段状态：每个组件显示准备、下载、记录 SHA-256、安装、验证五个阶段。
- 详细日志：默认保存在 `~/.ai-cli-installer/logs/`，包含时间、平台、URL、文件大小、本地 SHA-256、命令、耗时和失败原因。
- 下载恢复：Bash 版使用 `curl` 重试、超时和断点续传；失败时自动删除损坏的部分文件再重试。
- 失败隔离：一个组件失败后继续处理其他组件，最终汇总并返回非零退出码。
- 安全输出：不会打印完整环境变量，不会记录账号、Token 或 API Key。

> “本地 SHA-256”只是记录下载文件指纹，方便排错和复核；只有上游同时提供可信校验值时才能称为完整性验证。

## 支持平台

| 平台 | 支持情况 |
|---|---|
| Windows 10/11 | Windows PowerShell 5.1+，x64/ARM64 |
| macOS 12+ | Intel / Apple Silicon，兼容系统 Bash 3.2 |
| Debian 系 | Ubuntu、Debian、Kali、Linux Mint、Pop!_OS 等 |
| RPM 系 | Fedora、RHEL、Rocky、CentOS、openSUSE 等 |
| 其他 Linux | x86_64/ARM64，CC Switch 回退 AppImage |
| WSL1/WSL2 | Claude、Codex、Hermes；CC Switch GUI 建议装到 Windows 主机 |

## 最简单的交互式安装

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

### macOS / Linux / Kali / WSL

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash
```

菜单支持输入 `1,3,4` 一次选择多个组件。

## 直接指定组件

### 只安装 Codex 和 Hermes

Windows：

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Install codex,hermes
```

Kali / Linux / macOS / WSL：

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash -s -- --install codex,hermes
```

### 安装全部

```powershell
.\install.ps1 -Install all
```

```bash
./install.sh --install all
```

支持的组件名：`claude,codex,hermes,cc-switch,all`。

## 进度和日志参数

| 功能 | Bash | PowerShell |
|---|---|---|
| 禁用动态进度 | `--no-progress` | `-NoProgress` |
| 静默模式 | `--quiet` | `-Quiet` |
| 指定日志 | `--log-file PATH` | `-LogFile PATH` |
| 调试诊断 | `--debug` | `-DebugInstaller` |
| Dry-run | `--dry-run` | `-DryRun` |
| 非交互模式 | `--non-interactive` | `-NonInteractive` |

示例：

```bash
./install.sh --install all --no-progress --log-file ~/ai-cli-install.log
```

```powershell
.\install.ps1 -Install all -NoProgress -LogFile "$HOME\ai-cli-install.log"
```

默认日志目录：

```text
~/.ai-cli-installer/logs/
```

## Kali 推荐操作

先下载并审计脚本：

```bash
curl -fsSLO https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh
bash -n install.sh
less install.sh
chmod +x install.sh
```

运行 CC Switch 安装：

```bash
./install.sh --install cc-switch
```

无动画、便于复制日志：

```bash
./install.sh --install cc-switch --no-progress --log-file ~/cc-switch-install.log
```

只查看会执行的操作：

```bash
./install.sh --install all --dry-run --skip-network-check --no-progress
```

## 中国网络环境

当前进程使用本地代理：

```bash
./install.sh --install all --proxy http://127.0.0.1:7890
```

```powershell
.\install.ps1 -Install all -Proxy http://127.0.0.1:7890
```

只有 GitHub Release 下载需要特殊链路时，才显式指定自己信任的下载前缀：

```bash
./install.sh --install cc-switch --github-proxy https://your-trusted-proxy.example/
```

```powershell
.\install.ps1 -Install cc-switch -GitHubProxy https://your-trusted-proxy.example/
```

该服务能够看到或修改下载内容，默认不会启用任何镜像。

## 安装汇总和退出码

- `0`：所有选中组件成功，或用户主动退出。
- `1`：至少一个组件失败，但其他组件已经继续处理。
- `2`：参数、系统检测或初始化错误。

失败时查看最终输出给出的日志路径。日志不包含完整环境变量和密钥。

## 开发与容器验证

当前测试环境本身运行在 Docker 容器中。执行：

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
bash tests/container_matrix.sh
```

`container_matrix.sh` 会模拟 Kali、Debian ARM64、Fedora、Arch/AppImage 和 macOS dry-run 路径。GitHub Actions 另外使用真实 `kalilinux/kali-rolling` 容器运行完整测试。

## 安全说明

- Claude Code：`https://claude.ai/install.sh` / `install.ps1`
- Codex：`https://chatgpt.com/codex/install.sh` / `install.ps1`
- Hermes：`https://hermes-agent.nousresearch.com/install.sh` / `install.ps1`
- CC Switch：`farion1231/cc-switch` 官方 Release API 和安装包
- 自定义 GitHub 下载前缀只在用户明确传入时启用。
- 建议远程执行前先下载并审计脚本。

## 许可证

MIT。各组件分别遵循自身许可证、服务条款和地区可用性规则。
