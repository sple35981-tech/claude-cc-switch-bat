#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_NAME="Claude Code + CC Switch Installer"
CC_SWITCH_REPO="farion1231/cc-switch"
CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
GITHUB_API_URL="https://api.github.com/repos/${CC_SWITCH_REPO}/releases/latest"
CHANNEL="stable"
PROXY_URL=""
GITHUB_PROXY=""
SKIP_CLAUDE=0
SKIP_CC_SWITCH=0
DRY_RUN=0
NON_INTERACTIVE=0
SKIP_NETWORK_CHECK=0
TMP_DIR=""

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Claude Code + CC Switch 跨平台一键安装器

用法:
  ./install.sh [选项]

选项:
  --channel stable|latest   Claude Code 更新通道，默认 stable
  --proxy URL               为当前安装过程设置 HTTP/HTTPS 代理
  --github-proxy URL        为 GitHub 下载显式添加代理前缀
  --skip-claude             跳过 Claude Code
  --skip-cc-switch          跳过 CC Switch
  --dry-run                 仅显示将执行的操作，不下载或安装
  --non-interactive         非交互模式
  --skip-network-check      跳过安装前网络诊断
  -h, --help                显示帮助

示例:
  ./install.sh
  ./install.sh --channel latest
  ./install.sh --proxy http://127.0.0.1:7890
  ./install.sh --github-proxy https://your-trusted-proxy.example/
  ./install.sh --dry-run --skip-network-check
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      [[ $# -ge 2 ]] || die "--channel 缺少参数，可选 stable 或 latest"
      CHANNEL="$2"; shift 2 ;;
    --proxy)
      [[ $# -ge 2 ]] || die "--proxy 缺少 URL"
      PROXY_URL="$2"; shift 2 ;;
    --github-proxy)
      [[ $# -ge 2 ]] || die "--github-proxy 缺少 URL"
      GITHUB_PROXY="$2"; shift 2 ;;
    --skip-claude) SKIP_CLAUDE=1; shift ;;
    --skip-cc-switch) SKIP_CC_SWITCH=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --skip-network-check) SKIP_NETWORK_CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1（使用 --help 查看帮助）" ;;
  esac
done

[[ "$CHANNEL" == "stable" || "$CHANNEL" == "latest" ]] || die "--channel 只支持 stable 或 latest"
[[ $SKIP_CLAUDE -eq 0 || $SKIP_CC_SWITCH -eq 0 ]] || die "Claude Code 和 CC Switch 不能同时跳过"

if [[ -n "$PROXY_URL" ]]; then
  export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL"
  export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL"
fi

if [[ $NON_INTERACTIVE -eq 1 ]]; then
  export CI=1
  export DEBIAN_FRONTEND=noninteractive
fi

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

quote_cmd() {
  local out="" arg
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    out+="${arg} "
  done
  printf '%s' "${out% }"
}

run() {
  log "执行: $(quote_cmd "$@")"
  if [[ $DRY_RUN -eq 0 ]]; then
    "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

as_root() {
  if [[ $(id -u) -eq 0 ]]; then
    run "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo "$@"
  else
    die "安装系统软件需要 root 权限，但未找到 sudo"
  fi
}

apply_github_proxy() {
  local url="$1"
  if [[ -z "$GITHUB_PROXY" ]]; then
    printf '%s' "$url"
  else
    printf '%s%s' "${GITHUB_PROXY%/}/" "$url"
  fi
}

download() {
  local url="$1" dest="$2"
  log "下载: $url"
  if [[ $DRY_RUN -eq 1 ]]; then
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error \
      --retry 4 --retry-delay 2 --connect-timeout 15 --max-time 900 \
      --user-agent "cc-switch-installer/1.0" \
      -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --tries=4 --timeout=30 --user-agent="cc-switch-installer/1.0" -O "$dest" "$url"
  else
    die "需要 curl 或 wget 才能下载文件"
  fi
}

network_check() {
  [[ $SKIP_NETWORK_CHECK -eq 1 || $DRY_RUN -eq 1 ]] && return 0
  log "检查网络连通性（失败只提示，不会绕过服务地区或账号限制）"
  local url
  for url in "https://claude.ai" "https://api.github.com"; do
    if command -v curl >/dev/null 2>&1; then
      if ! curl --head --location --silent --show-error --connect-timeout 8 --max-time 20 "$url" >/dev/null; then
        warn "无法访问 $url；可使用 --proxy，GitHub 下载还可使用 --github-proxy"
      fi
    fi
  done
}

detect_os() {
  if [[ -n "${INSTALLER_TEST_OS:-}" ]]; then
    printf '%s' "$INSTALLER_TEST_OS"; return
  fi
  case "$(uname -s)" in
    Darwin) printf 'macos' ;;
    Linux) printf 'linux' ;;
    *) die "不支持的系统: $(uname -s)。Windows 请运行 install.ps1" ;;
  esac
}

detect_arch() {
  local machine="${INSTALLER_TEST_ARCH:-$(uname -m)}"
  case "$machine" in
    x86_64|amd64) printf 'x86_64' ;;
    arm64|aarch64) printf 'arm64' ;;
    *) die "不支持的 CPU 架构: $machine" ;;
  esac
}

detect_distro() {
  if [[ -n "${INSTALLER_TEST_DISTRO:-}" ]]; then
    printf '%s' "$INSTALLER_TEST_DISTRO"; return
  fi
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s' "${ID:-unknown}"
  else
    printf 'unknown'
  fi
}

make_temp_dir() {
  if [[ $DRY_RUN -eq 1 ]]; then
    TMP_DIR="${TMPDIR:-/tmp}/cc-installer-dry-run"
  else
    TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t cc-installer)"
  fi
}

install_claude() {
  [[ $SKIP_CLAUDE -eq 1 ]] && { log "已跳过 Claude Code"; return; }
  local installer="$TMP_DIR/claude-install.sh"
  log "准备从 Anthropic 官方地址安装 Claude Code（通道: $CHANNEL）"
  download "$CLAUDE_INSTALL_URL" "$installer"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "执行: bash $(printf '%q' "$installer") $(printf '%q' "$CHANNEL")"
    return
  fi
  chmod 700 "$installer"
  bash "$installer" "$CHANNEL"
}

release_asset_url() {
  local pattern="$1"
  if [[ -n "${INSTALLER_FAKE_ASSET_URL:-}" ]]; then
    printf '%s' "$INSTALLER_FAKE_ASSET_URL"
    return
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    local placeholder
    if [[ "$pattern" == *macOS* ]]; then
      placeholder="CC-Switch-LATEST-macOS.zip"
    elif [[ "$pattern" == *Linux-x86_64* ]]; then
      if [[ "$pattern" == *deb* ]]; then placeholder="CC-Switch-LATEST-Linux-x86_64.deb"
      elif [[ "$pattern" == *rpm* ]]; then placeholder="CC-Switch-LATEST-Linux-x86_64.rpm"
      else placeholder="CC-Switch-LATEST-Linux-x86_64.AppImage"; fi
    elif [[ "$pattern" == *Linux-arm64* ]]; then
      if [[ "$pattern" == *deb* ]]; then placeholder="CC-Switch-LATEST-Linux-arm64.deb"
      elif [[ "$pattern" == *rpm* ]]; then placeholder="CC-Switch-LATEST-Linux-arm64.rpm"
      else placeholder="CC-Switch-LATEST-Linux-arm64.AppImage"; fi
    else
      placeholder="CC-Switch-LATEST-package"
    fi
    printf 'https://github.com/%s/releases/latest/download/%s' "$CC_SWITCH_REPO" "$placeholder"
    return
  fi

  local json="$TMP_DIR/cc-switch-release.json"
  download "$GITHUB_API_URL" "$json"

  local url=""
  if command -v python3 >/dev/null 2>&1; then
    url="$(python3 - "$json" "$pattern" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding='utf-8') as f:
    release = json.load(f)
regex = re.compile(sys.argv[2], re.I)
for asset in release.get('assets', []):
    name = asset.get('name', '')
    url = asset.get('browser_download_url', '')
    if regex.search(name):
        print(url)
        break
PY
)"
  else
    url="$(grep -E '"browser_download_url"' "$json" | sed -E 's/.*"(https:[^"]+)".*/\1/' | grep -Ei "$pattern" | head -n 1 || true)"
  fi
  [[ -n "$url" ]] || die "未找到匹配资产: $pattern"
  case "$url" in
    https://github.com/*|https://objects.githubusercontent.com/*|https://github-releases.githubusercontent.com/*) ;;
    *) die "Release 返回了非 GitHub 下载地址，已拒绝: $url" ;;
  esac
  printf '%s' "$url"
}

install_cc_switch_macos() {
  if command -v brew >/dev/null 2>&1; then
    log "使用 Homebrew 安装 CC Switch"
    run brew install --cask cc-switch
    return
  fi

  local url asset extract app
  url="$(release_asset_url 'CC-Switch-v.*-macOS\.zip$')"
  asset="$TMP_DIR/cc-switch-macos.zip"
  extract="$TMP_DIR/cc-switch-macos"
  download "$(apply_github_proxy "$url")" "$asset"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "将解压 macOS ZIP 并复制应用到 /Applications"
    return
  fi
  need_cmd unzip
  mkdir -p "$extract"
  unzip -q "$asset" -d "$extract"
  app="$(find "$extract" -type d -name '*.app' -print | head -n 1)"
  [[ -n "$app" ]] || die "ZIP 中未找到 .app"
  if [[ -w /Applications ]]; then
    run ditto "$app" "/Applications/$(basename "$app")"
  else
    as_root ditto "$app" "/Applications/$(basename "$app")"
  fi
}

install_appimage() {
  local url="$1" asset="$TMP_DIR/cc-switch.AppImage"
  local target="$HOME/.local/bin/cc-switch.AppImage"
  local desktop="$HOME/.local/share/applications/cc-switch.desktop"
  download "$(apply_github_proxy "$url")" "$asset"
  run mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
  run cp "$asset" "$target"
  run chmod +x "$target"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "将创建桌面入口: $desktop"
  else
    cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CC Switch
Comment=Claude Code / Codex / Gemini CLI configuration manager
Exec="$target"
Terminal=false
Categories=Development;
EOF
  fi
  log "AppImage 已安装到 $target"
}

install_cc_switch_linux() {
  local distro="$1" arch="$2" ext pattern url asset
  case "$distro" in
    ubuntu|debian|linuxmint|pop|kali|zorin) ext='deb' ;;
    fedora|rhel|centos|rocky|almalinux|ol|opensuse*|sles) ext='rpm' ;;
    *) ext='AppImage' ;;
  esac

  pattern="CC-Switch-v.*-Linux-${arch}\.${ext}$"
  url="$(release_asset_url "$pattern")"
  asset="$TMP_DIR/$(basename "$url")"
  log "CC Switch 来源: ${CC_SWITCH_REPO}"

  case "$ext" in
    deb)
      download "$(apply_github_proxy "$url")" "$asset"
      if command -v apt >/dev/null 2>&1; then
        as_root apt install -y "$asset"
      else
        as_root dpkg -i "$asset"
      fi
      ;;
    rpm)
      download "$(apply_github_proxy "$url")" "$asset"
      if command -v dnf >/dev/null 2>&1; then
        as_root dnf install -y "$asset"
      elif command -v zypper >/dev/null 2>&1; then
        as_root zypper --non-interactive install "$asset"
      elif command -v yum >/dev/null 2>&1; then
        as_root yum install -y "$asset"
      else
        as_root rpm -Uvh "$asset"
      fi
      ;;
    AppImage) install_appimage "$url" ;;
  esac
}

install_cc_switch() {
  [[ $SKIP_CC_SWITCH -eq 1 ]] && { log "已跳过 CC Switch"; return; }
  local os="$1" arch="$2" distro="$3"
  log "准备安装 CC Switch（官方仓库: ${CC_SWITCH_REPO}）"
  case "$os" in
    macos) install_cc_switch_macos ;;
    linux) install_cc_switch_linux "$distro" "$arch" ;;
    *) die "不支持的系统: $os" ;;
  esac
}

verify_installation() {
  log "安装结果检查"
  if [[ $SKIP_CLAUDE -eq 0 ]]; then
    if command -v claude >/dev/null 2>&1; then
      claude --version || true
    else
      warn "当前 Shell 还找不到 claude。请重新打开终端，或把 ~/.local/bin 加入 PATH，然后运行 claude --version"
    fi
  fi
  if [[ $SKIP_CC_SWITCH -eq 0 ]]; then
    log "CC Switch 安装完成后可从应用菜单启动；Linux AppImage 用户也可运行 ~/.local/bin/cc-switch.AppImage"
  fi
}

main() {
  log "$PROGRAM_NAME"
  log "说明：本脚本不绕过 Claude 的地区、账号或服务条款限制。"
  make_temp_dir
  local os arch distro
  os="$(detect_os)"
  arch="$(detect_arch)"
  distro="unknown"
  [[ "$os" == "linux" ]] && distro="$(detect_distro)"
  log "检测到: OS=$os ARCH=$arch DISTRO=$distro"
  [[ -n "$PROXY_URL" ]] && log "已为当前进程启用代理: $PROXY_URL"
  [[ -n "$GITHUB_PROXY" ]] && warn "已启用用户指定的 GitHub 代理前缀，请确保该服务可信"
  network_check
  install_claude
  install_cc_switch "$os" "$arch" "$distro"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "Dry-run 完成，未修改系统"
  else
    verify_installation
    log "全部操作完成。运行 claude 开始登录，打开 CC Switch 配置供应商。"
  fi
}

main "$@"
