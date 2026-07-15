# AI CLI Installer Collector

一个面向 Windows、macOS、Linux、Kali 和 WSL 的四合一安装集合器，可以自由选择安装：

- Claude Code（Anthropic 官方安装器）
- OpenAI Codex CLI（OpenAI 官方安装器）
- Hermes Agent（Nous Research 官方安装器）
- CC Switch（`farion1231/cc-switch` 官方 GitHub Releases）

脚本不内置共享账号、API Key、第三方中转站或默认镜像，也不会绕过地区、账号或服务条款限制。

## 新版安装界面

真实终端会显示总进度条，每个组件固定经过四个阶段：

```text
============================================================
  AI CLI Installer Collector v3.0.0
  Claude Code / Codex / Hermes / CC Switch
============================================================
[##################------]  75% (11/15) CC Switch · 安装 · 安装 deb 包
```

CI、管道和没有 TTY 的环境会自动退化为稳定的逐行输出：

```text
[STEP 11/15]  73% CC Switch · 安装 · 安装 deb 包
```

每个组件都会记录：准备、下载、安装、验证、耗时、失败阶段和退出码。一个组件失败后，脚本会继续处理其他已选择组件，并在最后返回非零退出码。

## 一键运行

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/sple35981-tech/claude-cc-switch-bat/main/install.ps1 | iex
```

需要参数时建议先下载：

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

## 菜单选择

无参数运行时可以输入多个编号，例如 `1,3,4`：

```text
1) Claude Code
2) OpenAI Codex CLI
3) Nous Research Hermes Agent
4) CC Switch
5) 全部安装
0) 退出
```

组件名称支持：

```text
claude,codex,hermes,cc-switch,all
```

## 常用参数

| 功能 | Bash | PowerShell |
|---|---|---|
| 选择组件 | `--install all` | `-Install all` |
| Claude 通道 | `--channel latest` | `-Channel latest` |
| 当前进程代理 | `--proxy URL` | `-Proxy URL` |
| GitHub 下载前缀 | `--github-proxy URL` | `-GitHubProxy URL` |
| 只预览 | `--dry-run` | `-DryRun` |
| 非交互 | `--non-interactive` | `-NonInteractive` |
| 跳过网络预检 | `--skip-network-check` | `-SkipNetworkCheck` |
| 静默终端 | `--quiet` | `-Quiet` |
| 禁用动态进度 | `--no-progress` | `-NoProgress` |
| 指定日志 | `--log-file PATH` | `-LogFile PATH` |
| Bash 调试日志 | `--debug` | — |
| Bash 保留临时文件 | `--keep-temp` | — |

Kali 示例：

```bash
./install.sh --install all --log-file ~/ai-cli-install.log
```

服务器/CI 示例：

```bash
./install.sh --install codex,hermes \
  --non-interactive --no-progress --log-file ./installer.log
```

## 日志与排错

Bash 默认日志目录：

```text
~/.local/state/ai-cli-installer/logs/
```

Windows 默认日志目录：

```text
%LOCALAPPDATA%\ai-cli-installer\logs\
```

日志包含系统信息、官方 URL、命令、阶段、耗时和错误信息。代理 URL 中的用户名/密码会被遮盖。脚本不会主动记录 Token 或 API Key。

下载完成后，脚本会记录文件的本地 SHA-256 指纹。该指纹用于排错和比对，不代表上游发布方提供了签名或官方校验值。

### 中国网络环境

```bash
./install.sh --install all --proxy http://127.0.0.1:7890
```

```powershell
.\install.ps1 -Install all -Proxy http://127.0.0.1:7890
```

GitHub Release 确实需要额外链路时，可以显式提供自己信任的下载前缀。脚本默认不启用任何镜像。

## 安装前审计

```bash
bash -n install.sh
./install.sh --install all --dry-run --skip-network-check --no-progress
```

```powershell
.\install.ps1 -Install all -DryRun -SkipNetworkCheck -NoProgress
```

## 开发与验证

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
bash tests/container_matrix.sh
```

容器矩阵使用假下载器和假包管理器，不会安装真实软件，覆盖：

- Kali / Debian：DEB
- Fedora：RPM
- Arch/其他 Linux：AppImage
- macOS：Homebrew 路径
- 无 TTY 输出
- 组件故障继续执行
- GitHub Release URL 污染回归

GitHub Actions 还会在 Ubuntu、macOS 和 Windows 上验证 Bash/PowerShell 语法和全组件 dry-run。

## 许可证

MIT。各组件仍分别遵循自身许可证、服务条款和地区可用性规则。
