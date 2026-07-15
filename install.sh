#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_NAME="AI CLI Installer Collector"
CC_SWITCH_REPO="farion1231/cc-switch"
CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
CODEX_INSTALL_URL="https://chatgpt.com/codex/install.sh"
HERMES_INSTALL_URL="https://hermes-agent.nousresearch.com/install.sh"
GITHUB_API_URL="https://api.github.com/repos/${CC_SWITCH_REPO}/releases/latest"
CHANNEL="stable"
PROXY_URL=""
GITHUB_PROXY=""
RAW_SELECTION=""
SKIP_CLAUDE=0
SKIP_CODEX=0
SKIP_HERMES=0
SKIP_CC_SWITCH=0
DRY_RUN=0
NON_INTERACTIVE=0
SKIP_NETWORK_CHECK=0
TMP_DIR=""
SELECTED_COMPONENTS=()
SUCCEEDED_COMPONENTS=()
FAILED_COMPONENTS=()
SKIPPED_COMPONENTS=()

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Claude Code / Codex / Hermes / CC Switch 跨平台安装集合器

用法:
  ./install.sh [选项]

组件:
  claude       Claude Code
  codex        OpenAI Codex CLI
  hermes       Nous Research Hermes Agent
  cc-switch    CC Switch 桌面配置管理器
  all          安装以上全部组件

选项:
  --install LIST            选择组件，逗号分隔，例如 codex,hermes 或 all
  --channel stable|latest   Claude Code 更新通道，默认 stable
  --proxy URL               为当前安装过程设置 HTTP/HTTPS 代理
  --github-proxy URL        为 GitHub Release 下载显式添加代理前缀
  --skip-claude             从选择中移除 Claude Code（兼容旧参数）
  --skip-codex              从选择中移除 Codex
  --skip-hermes             从选择中移除 Hermes
  --skip-cc-switch          从选择中移除 CC Switch（兼容旧参数）
  --dry-run                 仅显示将执行的操作，不下载或安装
  --non-interactive         禁用菜单；未选择时默认 Claude Code + CC Switch
  --skip-network-check      跳过安装前网络诊断
  -h, --help                显示帮助

示例:
  ./install.sh                         # 有终端时显示选择菜单
  ./install.sh --install all
  ./install.sh --install codex,hermes
  ./install.sh --install claude --channel latest
  ./install.sh --proxy http://127.0.0.1:7890
  ./install.sh --dry-run --install all --skip-network-check
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      [[ $# -ge 2 ]] || die "--install 缺少组件列表"
      RAW_SELECTION="$2"; shift 2 ;;
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
    --skip-codex) SKIP_CODEX=1; shift ;;
    --skip-hermes) SKIP_HERMES=1; shift ;;
    --skip-cc-switch) SKIP_CC_SWITCH=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --skip-network-check) SKIP_NETWORK_CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1（使用 --help 查看帮助）" ;;
  esac
done

[[ "$CHANNEL" == "stable" || "$CHANNEL" == "latest" ]] || die "--channel 只支持 stable 或 latest"

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

contains_component() {
  local wanted="$1" item
  [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]] && return 1
  for item in "${SELECTED_COMPONENTS[@]}"; do
    [[ "$item" == "$wanted" ]] && return 0
  done
  return 1
}

append_unique_component() {
  local component="$1"
  if ! contains_component "$component"; then
    SELECTED_COMPONENTS+=("$component")
  fi
}

component_label() {
  case "$1" in
    claude) printf 'Claude Code' ;;
    codex) printf 'Codex CLI' ;;
    hermes) printf 'Hermes Agent' ;;
    cc-switch) printf 'CC Switch' ;;
    *) printf '%s' "$1" ;;
  esac
}

normalize_selection_token() {
  local token="$1"
  token="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$token" in
    1|claude|claude-code|claudecode) printf 'claude' ;;
    2|codex|codex-cli|codexcli) printf 'codex' ;;
    3|hermes|hermes-agent|hermesagent) printf 'hermes' ;;
    4|cc-switch|ccswitch|cc_switch) printf 'cc-switch' ;;
    5|all|'*') printf 'all' ;;
    0|exit|quit|q) printf 'exit' ;;
    '') printf '' ;;
    *) die "未知组件: ${token}。可选 claude、codex、hermes、cc-switch、all" ;;
  esac
}

parse_selection() {
  local raw="$1" normalized token old_ifs
  raw="${raw// /,}"
  old_ifs="$IFS"
  IFS=','
  # shellcheck disable=SC2206
  local tokens=( $raw )
  IFS="$old_ifs"

  for token in "${tokens[@]}"; do
    normalized="$(normalize_selection_token "$token")"
    case "$normalized" in
      '') ;;
      exit) exit 0 ;;
      all)
        append_unique_component claude
        append_unique_component codex
        append_unique_component hermes
        append_unique_component cc-switch
        ;;
      *) append_unique_component "$normalized" ;;
    esac
  done
}

has_interactive_tty() {
  [[ -t 0 || -t 1 || -t 2 ]] && [[ -r /dev/tty && -w /dev/tty ]]
}

show_menu_and_read_selection() {
  local selection=""
  cat >/dev/tty <<'EOF'

请选择要安装的组件（可多选，例如 1,3,4）：
  1) Claude Code
  2) OpenAI Codex CLI
  3) Nous Research Hermes Agent
  4) CC Switch
  5) 全部安装
  0) 退出
EOF
  printf '请输入选择: ' >/dev/tty
  IFS= read -r selection </dev/tty || die "无法读取选择"
  printf '%s' "$selection"
}

remove_skipped_components() {
  local filtered=() item
  for item in "${SELECTED_COMPONENTS[@]}"; do
    case "$item" in
      claude) [[ $SKIP_CLAUDE -eq 1 ]] && { SKIPPED_COMPONENTS+=("Claude Code"); continue; } ;;
      codex) [[ $SKIP_CODEX -eq 1 ]] && { SKIPPED_COMPONENTS+=("Codex CLI"); continue; } ;;
      hermes) [[ $SKIP_HERMES -eq 1 ]] && { SKIPPED_COMPONENTS+=("Hermes Agent"); continue; } ;;
      cc-switch) [[ $SKIP_CC_SWITCH -eq 1 ]] && { SKIPPED_COMPONENTS+=("CC Switch"); continue; } ;;
    esac
    filtered+=("$item")
  done
  SELECTED_COMPONENTS=("${filtered[@]}")
}

resolve_selection() {
  local selection="$RAW_SELECTION"
  if [[ -z "$selection" && -n "${INSTALLER_TEST_SELECTION:-}" ]]; then
    selection="$INSTALLER_TEST_SELECTION"
  elif [[ -z "$selection" && $NON_INTERACTIVE -eq 0 ]] && has_interactive_tty; then
    selection="$(show_menu_and_read_selection)"
  elif [[ -z "$selection" ]]; then
    selection="claude,cc-switch"
    log "未检测到交互终端，使用兼容默认选择: Claude Code + CC Switch"
  fi

  parse_selection "$selection"
  remove_skipped_components
  [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]] || die "没有可安装组件，请使用 --install 选择至少一项"
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
      --user-agent "ai-cli-installer/2.0" \
      -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --tries=4 --timeout=30 --user-agent="ai-cli-installer/2.0" -O "$dest" "$url"
  else
    die "需要 curl 或 wget 才能下载文件"
  fi
}

network_check_url() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    if ! curl --head --location --silent --show-error --connect-timeout 8 --max-time 20 "$url" >/dev/null; then
      warn "无法访问 ${url}；可使用 --proxy，GitHub 下载还可使用 --github-proxy"
    fi
  fi
}

network_check() {
  [[ $SKIP_NETWORK_CHECK -eq 1 || $DRY_RUN -eq 1 ]] && return 0
  log "检查所选组件的网络连通性（失败只提示，不绕过地区、账号或服务条款限制）"
  contains_component claude && network_check_url "https://claude.ai"
  contains_component codex && network_check_url "https://chatgpt.com"
  contains_component hermes && network_check_url "https://hermes-agent.nousresearch.com"
  contains_component cc-switch && network_check_url "https://api.github.com"
  return 0
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
    TMP_DIR="${TMPDIR:-/tmp}/ai-cli-installer-dry-run"
  else
    TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t ai-cli-installer)"
  fi
}

maybe_fail_component() {
  local component="$1"
  if [[ "${INSTALLER_TEST_FAIL_COMPONENT:-}" == "$component" ]]; then
    warn "测试注入失败: $(component_label "$component")"
    return 97
  fi
}

install_claude() {
  local installer="$TMP_DIR/claude-install.sh"
  log "准备从 Anthropic 官方地址安装 Claude Code（通道: ${CHANNEL}）"
  download "$CLAUDE_INSTALL_URL" "$installer"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "执行: bash $(printf '%q' "$installer") $(printf '%q' "$CHANNEL")"
    return
  fi
  chmod 700 "$installer"
  bash "$installer" "$CHANNEL"
}

install_codex() {
  local installer="$TMP_DIR/codex-install.sh"
  log "准备从 OpenAI 官方地址安装 Codex CLI"
  download "$CODEX_INSTALL_URL" "$installer"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "执行: sh $(printf '%q' "$installer")"
    return
  fi
  chmod 700 "$installer"
  sh "$installer"
}

install_hermes() {
  local installer="$TMP_DIR/hermes-install.sh"
  log "准备从 Nous Research 官方地址安装 Hermes Agent"
  download "$HERMES_INSTALL_URL" "$installer"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "执行: bash $(printf '%q' "$installer")"
    return
  fi
  chmod 700 "$installer"
  bash "$installer"
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
  download "$GITHUB_API_URL" "$json" >&2

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

  [[ -n "$url" ]] || die "未找到匹配的 CC Switch 安装包: $pattern"
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
  local os="$1" arch="$2" distro="$3"
  log "准备安装 CC Switch（官方仓库: ${CC_SWITCH_REPO}）"
  case "$os" in
    macos) install_cc_switch_macos ;;
    linux) install_cc_switch_linux "$distro" "$arch" ;;
    *) die "不支持的系统: $os" ;;
  esac
}

install_component() {
  local component="$1" os="$2" arch="$3" distro="$4"
  maybe_fail_component "$component"
  case "$component" in
    claude) install_claude ;;
    codex) install_codex ;;
    hermes) install_hermes ;;
    cc-switch) install_cc_switch "$os" "$arch" "$distro" ;;
    *) die "内部错误，未知组件: $component" ;;
  esac
}

run_component() {
  local component="$1" os="$2" arch="$3" distro="$4" label status
  label="$(component_label "$component")"
  printf '\n'
  log "========== $label =========="
  set +e
  (
    set -Eeuo pipefail
    install_component "$component" "$os" "$arch" "$distro"
  )
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    SUCCEEDED_COMPONENTS+=("$label")
    log "$label: 成功"
  else
    FAILED_COMPONENTS+=("$label")
    warn "$label: 失败（退出码 ${status}），继续处理其他组件"
  fi
}

join_by_comma() {
  local first=1 item
  for item in "$@"; do
    if [[ $first -eq 0 ]]; then printf ', '; fi
    printf '%s' "$item"
    first=0
  done
}

verify_installation() {
  [[ $DRY_RUN -eq 1 ]] && return
  log "安装结果检查"
  if contains_component claude; then
    command -v claude >/dev/null 2>&1 && claude --version || warn "当前 Shell 还找不到 claude，请重新打开终端"
  fi
  if contains_component codex; then
    command -v codex >/dev/null 2>&1 && codex --version || warn "当前 Shell 还找不到 codex，请重新打开终端"
  fi
  if contains_component hermes; then
    command -v hermes >/dev/null 2>&1 && hermes --version || warn "当前 Shell 还找不到 hermes，请重新打开终端"
  fi
  if contains_component cc-switch; then
    log "CC Switch 可从应用菜单启动；AppImage 路径为 ~/.local/bin/cc-switch.AppImage"
  fi
}

print_summary() {
  printf '\n'
  log "========== 安装汇总 =========="
  if [[ ${#SUCCEEDED_COMPONENTS[@]} -gt 0 ]]; then
    log "成功: $(join_by_comma "${SUCCEEDED_COMPONENTS[@]}")"
  fi
  if [[ ${#SKIPPED_COMPONENTS[@]} -gt 0 ]]; then
    log "跳过: $(join_by_comma "${SKIPPED_COMPONENTS[@]}")"
  fi
  if [[ ${#FAILED_COMPONENTS[@]} -gt 0 ]]; then
    warn "失败: $(join_by_comma "${FAILED_COMPONENTS[@]}")"
  fi
}

main() {
  log "$PROGRAM_NAME"
  log "说明：只使用各项目官方安装源，不绕过地区、账号或服务条款限制。"
  resolve_selection
  make_temp_dir

  local os arch distro item
  os="$(detect_os)"
  arch="$(detect_arch)"
  distro="unknown"
  [[ "$os" == "linux" ]] && distro="$(detect_distro)"
  log "检测到: OS=$os ARCH=$arch DISTRO=$distro"
  log "已选择: $(join_by_comma "${SELECTED_COMPONENTS[@]}")"
  [[ -n "$PROXY_URL" ]] && log "已为当前进程启用代理: $PROXY_URL"
  [[ -n "$GITHUB_PROXY" ]] && warn "已启用用户指定的 GitHub 代理前缀，请确保该服务可信"

  network_check
  for item in "${SELECTED_COMPONENTS[@]}"; do
    run_component "$item" "$os" "$arch" "$distro"
  done

  verify_installation
  print_summary
  if [[ $DRY_RUN -eq 1 ]]; then
    log "Dry-run 完成，未修改系统"
  fi
  [[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]
}

main "$@"
