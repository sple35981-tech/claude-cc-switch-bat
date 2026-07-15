# Claude Code + CC Switch 跨平台一键安装器

面向 Windows、macOS、Linux 和 WSL 的一键安装脚本，自动安装：

- **Claude Code**：使用 Anthropic 官方原生安装器。
- **CC Switch**：使用 [`farion1231/cc-switch`](https://github.com/farion1231/cc-switch) 官方 GitHub Releases 最新版本。

脚本针对中国用户常见的网络问题加入了代理参数、GitHub 下载前缀、超时重试、网络诊断和 dry-run，但**不会绕过 Claude 的地区限制、账号限制或服务条款**，也不会内置任何第三方中转站、共享账号或 API Key。

## 支持平台

| 平台 | 支持范围 | CC Switch 安装方式 |
|---|---|---|
| Windows | Windows 10/11，x64/ARM64 | MSI |
| macOS | macOS 12+，Intel/Apple Silicon | Homebrew；无 Homebrew 时使用官方 ZIP |
| Debian 系 | Ubuntu、Debian、Kali、Linux Mint、Pop!_OS 等 | DEB |
| RPM 系 | Fedora、RHEL、Rocky、CentOS、openSUSE 等 | RPM |
| 其他 Linux | x86_64/ARM64 | AppImage |
| WSL | WSL 1/2 | 安装 Claude Code；CC Switch GUI 更建议装在 Windows 主机 |

## 一键安装

### Windows PowerShell

直接运行：

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

需要传参数时，先下载再运行：

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Channel stable
```

也可以下载整个仓库后双击 `install.cmd`，或在 CMD 中运行：

```cmd
install.cmd -Channel latest
```

### macOS / Linux / WSL

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash
```

需要参数时：

```bash
curl -fsSL https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh | bash -s -- --channel latest
```

更重视审计时，建议先下载并查看脚本：

```bash
curl -fsSLO https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.sh
less install.sh
chmod +x install.sh
./install.sh
```

## 中国网络环境用法

### 使用本地代理

Windows：

```powershell
.\install.ps1 -Proxy http://127.0.0.1:7890
```

macOS / Linux / WSL：

```bash
./install.sh --proxy http://127.0.0.1:7890
```

脚本只为当前安装进程设置 `HTTP_PROXY` 和 `HTTPS_PROXY`，不会永久修改系统代理。

### GitHub 下载使用自定义前缀

只有 GitHub Release 下载慢时，可以显式指定你自己信任的下载前缀：

```powershell
.\install.ps1 -GitHubProxy https://your-trusted-proxy.example/
```

```bash
./install.sh --github-proxy https://your-trusted-proxy.example/
```

该前缀会拼接到原始 GitHub 下载 URL 前。代理服务可以看到或修改下载内容，因此不要使用来源不明的服务。脚本默认不会启用任何镜像。

### 跳过网络预检

```powershell
.\install.ps1 -SkipNetworkCheck
```

```bash
./install.sh --skip-network-check
```

这只会跳过预检，不会让无法访问的下载地址变得可用。

## 常用参数

| 功能 | Bash | PowerShell |
|---|---|---|
| 稳定通道 | `--channel stable` | `-Channel stable` |
| 最新通道 | `--channel latest` | `-Channel latest` |
| 当前进程代理 | `--proxy URL` | `-Proxy URL` |
| GitHub 下载前缀 | `--github-proxy URL` | `-GitHubProxy URL` |
| 跳过 Claude Code | `--skip-claude` | `-SkipClaude` |
| 跳过 CC Switch | `--skip-cc-switch` | `-SkipCCSwitch` |
| 只显示操作 | `--dry-run` | `-DryRun` |
| 跳过网络预检 | `--skip-network-check` | `-SkipNetworkCheck` |

查看完整帮助：

```bash
./install.sh --help
```

```powershell
Get-Help .\install.ps1 -Detailed
```

## Dry-run 审计

在真正安装前检查将执行的操作：

```bash
./install.sh --dry-run --skip-network-check
```

```powershell
.\install.ps1 -DryRun -SkipNetworkCheck
```

正常情况下，dry-run 不下载文件、不调用包管理器、不修改系统。

## 安装后检查

重新打开终端，然后运行：

```bash
claude --version
claude doctor
```

启动 Claude Code：

```bash
claude
```

CC Switch 可从 Windows 开始菜单、macOS Launchpad 或 Linux 应用菜单启动。AppImage 回退安装位于：

```text
~/.local/bin/cc-switch.AppImage
```

## 常见问题

### 安装后提示 `claude: command not found`

关闭并重新打开终端。macOS/Linux/WSL 还可检查：

```bash
export PATH="$HOME/.local/bin:$PATH"
claude --version
```

### Windows 执行策略阻止脚本

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

这只对本次 PowerShell 进程生效。

### GitHub API 访问失败

先确认浏览器能访问 GitHub，随后使用 `--proxy` / `-Proxy`。只有 Release 文件下载需要特殊链路时，再使用用户显式指定的 GitHub 下载前缀。

### WSL 里要不要安装 CC Switch？

Claude Code 应安装在你的项目所在环境。CC Switch 是桌面 GUI，在 WSL 场景通常更适合安装到 Windows 主机，再管理 Windows 侧配置；脚本仍可在带 GUI 支持的 Linux 环境中安装它。

## 安全说明

- Claude Code 安装脚本来自 `https://claude.ai/install.sh` 或 `https://claude.ai/install.ps1`。
- CC Switch Release 元数据与安装包来自 `farion1231/cc-switch` 官方 GitHub 仓库。
- 自定义 GitHub 下载前缀只在用户显式传入时启用。
- 不收集账号、Token、API Key、机器标识或使用数据。
- 建议在执行远程脚本前先下载并审计内容。

## 开发与测试

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
./install.sh --dry-run --skip-network-check
```

GitHub Actions 会在 Ubuntu、macOS 和 Windows 上运行测试。

## 许可证

MIT。CC Switch 与 Claude Code 分别遵循各自项目和服务的许可证、条款与地区可用性规则。
