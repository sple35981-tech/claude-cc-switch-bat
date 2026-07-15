# Claude Code / Codex / Hermes / CC Switch 一键安装集合器

面向 Windows、macOS、Linux、Kali 和 WSL 的四合一安装器。一个脚本可以交互选择安装：

- Claude Code：Anthropic 官方安装器
- OpenAI Codex CLI：OpenAI 官方安装器
- Hermes Agent：Nous Research 官方安装器
- CC Switch：`farion1231/cc-switch` 官方 GitHub Releases

脚本不内置第三方中转站、共享账号、API Key 或默认镜像。针对中国网络环境提供当前进程代理、自定义 GitHub 下载前缀、重试和网络诊断，但不会绕过地区、账号或服务条款限制。

## 新版安装体验

每个组件都显示四个真实阶段：

```text
准备 → 下载 → 安装 → 验证
```

交互式终端显示总进度条、当前组件和阶段；CI、重定向输出、SSH 无 TTY 或 `--no-progress` 会自动使用稳定的逐行输出。最终汇总成功、跳过、失败阶段、退出码、总耗时和详细日志路径。

```text
[PROGRESS] [##############--------------] 50% OK Codex CLI / 下载 - 安装器已准备
[SUMMARY] 成功: Codex CLI, Hermes Agent
[SUMMARY] 耗时: 18 秒
[SUMMARY] 详细日志: ~/.local/state/ai-cli-installer/install-....log
```

## 一键安装

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

需要参数时先下载：

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Install codex,hermes
```

### macOS / Linux / Kali / WSL

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash
```

直接指定组件：

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh \
  | bash -s -- --install codex,hermes
```

支持的组件名：`claude,codex,hermes,cc-switch,all`。

## 进度、日志与安静模式

### 禁用动态进度条

适合日志采集、CI 或终端显示异常时：

```bash
./install.sh --install all --no-progress
```

```powershell
.\install.ps1 -Install all -NoProgress
```

### 只显示警告、错误和汇总

```bash
./install.sh --install all --quiet
```

```powershell
.\install.ps1 -Install all -Quiet
```

### 指定日志文件

```bash
./install.sh --install cc-switch --log-file ./install.log
```

```powershell
.\install.ps1 -Install cc-switch -LogFile .\install.log
```

非 dry-run 默认自动创建 UTF-8 日志。代理 URL 中的用户名和密码、Authorization 内容和常见 API Key 环境变量会在日志中脱敏。日志文件默认仅当前用户可读。

## 中国网络环境

本地代理只对当前安装进程生效：

```bash
./install.sh --install all --proxy http://127.0.0.1:7890
```

```powershell
.\install.ps1 -Install all -Proxy http://127.0.0.1:7890
```

只有 GitHub Release 下载需要特殊链路时，才使用自己信任的前缀：

```bash
./install.sh --install cc-switch --github-proxy https://your-trusted-proxy.example/
```

```powershell
.\install.ps1 -Install cc-switch -GitHubProxy https://your-trusted-proxy.example/
```

## Dry-run 审计

不会下载或安装：

```bash
./install.sh --install all --dry-run --skip-network-check --no-progress
```

```powershell
.\install.ps1 -Install all -DryRun -SkipNetworkCheck -NoProgress
```

## 退出状态

- `0`：所有选中组件安装流程成功；验证阶段的“需要重新打开终端”属于警告。
- `1`：至少一个组件失败，但其他组件仍会继续处理。
- `2`：参数、平台或初始化错误，无法开始安装。

自动化脚本应检查 exit code，并在失败时读取汇总中的“失败阶段”和日志文件。

## 常用参数

| 功能 | Bash | PowerShell |
|---|---|---|
| 选择组件 | `--install LIST` | `-Install LIST` |
| Claude 通道 | `--channel stable\|latest` | `-Channel stable\|latest` |
| 当前进程代理 | `--proxy URL` | `-Proxy URL` |
| GitHub 下载前缀 | `--github-proxy URL` | `-GitHubProxy URL` |
| 自定义日志 | `--log-file PATH` | `-LogFile PATH` |
| 禁用动态进度 | `--no-progress` | `-NoProgress` |
| 安静模式 | `--quiet` | `-Quiet` |
| 审计模式 | `--dry-run` | `-DryRun` |
| 非交互模式 | `--non-interactive` | `-NonInteractive` |
| 跳过网络检查 | `--skip-network-check` | `-SkipNetworkCheck` |

## 验证

仓库包含 Python 单元测试和命令沙箱矩阵，覆盖 Kali/DEB、Fedora/RPM、Arch/AppImage、macOS ARM64、无 TTY、失败继续执行、日志脱敏和 Release URL 污染回归。

```bash
python3 -m unittest discover -s tests -v
python3 tests/container_matrix.py
bash -n install.sh
./install.sh --install all --dry-run --skip-network-check --no-progress
```

GitHub Actions 在 Ubuntu、macOS 和 Windows PowerShell 5.1 上继续验证。
