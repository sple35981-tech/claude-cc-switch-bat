#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_NAME="AI CLI Installer Collector"
PROGRAM_VERSION="3.0.0"
CC_SWITCH_REPO="farion1231/cc-switch"
CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
CODEX_INSTALL_URL="https://chatgpt.com/codex/install.sh"
HERMES_INSTALL_URL="https://hermes-agent.nousresearch.com/install.sh"
GITHUB_API_URL="https://api.github.com/repos/${CC_SWITCH_REPO}/releases/latest"

CHANNEL="stable"
PROXY_URL=""
GITHUB_PROXY=""
RAW_SELECTION=""
LOG_FILE=""
LOG_FILE_EXPLICIT=0
SKIP_CLAUDE=0
SKIP_CODEX=0
SKIP_HERMES=0
SKIP_CC_SWITCH=0
DRY_RUN=0
NON_INTERACTIVE=0
SKIP_NETWORK_CHECK=0
NO_PROGRESS=0
QUIET=0
TMP_DIR=""
LOG_ENABLED=0
START_EPOCH=0
RUN_STARTED_AT=""
TOTAL_STEPS=0
COMPLETED_STEPS=0
CURRENT_COMPONENT=""
CURRENT_STAGE=""
CURRENT_COMPONENT_STAGE=0
LAST_FAILURE_STAGE=""
LAST_FAILURE_DETAIL=""

SELECTED_COMPONENTS=()
SUCCEEDED_COMPONENTS=()
FAILED_COMPONENTS=()
FAILED_DETAILS=()
SKIPPED_COMPONENTS=()

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
  --skip-claude             从选择中移除 Claude Code
  --skip-codex              从选择中移除 Codex
  --skip-hermes             从选择中移除 Hermes
  --skip-cc-switch          从选择中移除 CC Switch
  --log-file PATH           指定详细安装日志路径
  --no-progress             禁用动态进度条，使用稳定的逐行输出
  --quiet                   仅显示警告、错误和最终汇总
  --dry-run                 仅显示计划，不下载或安装
  --non-interactive         禁用菜单；未选择时默认 Claude Code + CC Switch
  --skip-network-check      跳过安装前网络诊断
  -h, --help                显示帮助

示例:
  ./install.sh
  ./install.sh --install all
  ./install.sh --install codex,hermes --no-progress
  ./install.sh --install cc-switch --log-file ./install.log
  ./install.sh --proxy http://127.0.0.1:7890
  ./install.sh --dry-run --install all --skip-network-check
EOF
}

fatal() {
  emit ERROR "$*"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) [[ $# -ge 2 ]] || { printf '[ERROR] --install 缺少组件列表\n' >&2; exit 2; }; RAW_SELECTION="$2"; shift 2 ;;
    --channel) [[ $# -ge 2 ]] || { printf '[ERROR] --channel 缺少参数\n' >&2; exit 2; }; CHANNEL="$2"; shift 2 ;;
    --proxy) [[ $# -ge 2 ]] || { printf '[ERROR] --proxy 缺少 URL\n' >&2; exit 2; }; PROXY_URL="$2"; shift 2 ;;
    --github-proxy) [[ $# -ge 2 ]] || { printf '[ERROR] --github-proxy 缺少 URL\n' >&2; exit 2; }; GITHUB_PROXY="$2"; shift 2 ;;
    --skip-claude) SKIP_CLAUDE=1; shift ;;
    --skip-codex) SKIP_CODEX=1; shift ;;
    --skip-hermes) SKIP_HERMES=1; shift ;;
    --skip-cc-switch) SKIP_CC_SWITCH=1; shift ;;
    --log-file) [[ $# -ge 2 ]] || { printf '[ERROR] --log-file 缺少路径\n' >&2; exit 2; }; LOG_FILE="$2"; LOG_FILE_EXPLICIT=1; shift 2 ;;
    --no-progress) NO_PROGRESS=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --skip-network-check) SKIP_NETWORK_CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '[ERROR] 未知参数: %s（使用 --help 查看帮助）\n' "$1" >&2; exit 2 ;;
  esac
done

[[ "$CHANNEL" == "stable" || "$CHANNEL" == "latest" ]] || { printf '[ERROR] --channel 只支持 stable 或 latest\n' >&2; exit 2; }

if [[ -n "$PROXY_URL" ]]; then
  export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL"
  export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL"
fi
if [[ $NON_INTERACTIVE -eq 1 ]]; then
  export CI=1
  export DEBIAN_FRONTEND=noninteractive
fi

is_interactive_output() {
  [[ $NO_PROGRESS -eq 0 && $QUIET -eq 0 && -t 2 && -z "${CI:-}" && "${TERM:-dumb}" != "dumb" ]]
}

redact_text() {
  local text="$*"
  case "$text" in
    *://*@*|*[Aa]uthorization:*|*ANTHROPIC_AUTH_TOKEN=*|*OPENAI_API_KEY=*|*NOUS_API_KEY=*)
      printf '%s' "$text" | sed -E \
        -e 's#(https?://)[^/@[:space:]]+@#\1***@#g' \
        -e 's#([Aa]uthorization:[[:space:]]*(Bearer|Basic))[[:space:]]+[^[:space:]]+#\1 ***#g' \
        -e 's#((ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|NOUS_API_KEY)=)[^[:space:]]+#\1[REDACTED]#g'
      ;;
    *) printf '%s' "$text" ;;
  esac
}

log_write() {
  [[ $LOG_ENABLED -eq 1 ]] || return 0
  local level="$1"; shift
  printf '%s +%ss [%s] %s\n' "$RUN_STARTED_AT" "$SECONDS" "$level" "$*" >> "$LOG_FILE"
}

emit() {
  local level="$1"; shift
  local clean prefix
  clean="$(redact_text "$*")"
  log_write "$level" "$clean"
  if [[ $QUIET -eq 1 ]]; then
    case "$level" in WARN|ERROR|SUMMARY) ;; *) return 0 ;; esac
  fi
  case "$level" in
    INFO) prefix='[INFO]' ;;
    STEP) prefix='[STEP]' ;;
    OK) prefix='[ OK ]' ;;
    WARN) prefix='[WARN]' ;;
    ERROR) prefix='[ERROR]' ;;
    PROGRESS) prefix='[PROGRESS]' ;;
    SUMMARY) prefix='[SUMMARY]' ;;
    *) prefix="[$level]" ;;
  esac
  printf '%s %s\n' "$prefix" "$clean" >&2
}

init_log() {
  if [[ $DRY_RUN -eq 1 && $LOG_FILE_EXPLICIT -eq 0 ]]; then
    LOG_ENABLED=0
    return 0
  fi
  if [[ -z "$LOG_FILE" ]]; then
    local state_root
    state_root="${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/ai-cli-installer"
    LOG_FILE="${state_root}/install-$(date '+%Y%m%d-%H%M%S')-$$.log"
  fi
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"
  chmod 600 "$LOG_FILE" 2>/dev/null || true
  LOG_ENABLED=1
  log_write INFO "${PROGRAM_NAME} v${PROGRAM_VERSION} started"
}

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

quote_cmd() {
  local out="" arg quoted
  for arg in "$@"; do
    printf -v quoted '%q' "$arg"
    out="${out}${quoted} "
  done
  printf '%s' "${out% }"
}

run_cmd() {
  local shown
  shown="$(quote_cmd "$@")"
  emit INFO "执行: ${shown}"
  if [[ $DRY_RUN -eq 1 ]]; then
    return 0
  fi
  "$@"
}

as_root() {
  if [[ $(id -u) -eq 0 ]]; then
    run_cmd "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run_cmd sudo "$@"
  else
    emit ERROR "安装系统软件需要 root 权限，但未找到 sudo"
    return 126
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
    *) fatal "未知组件: ${token}。可选 claude、codex、hermes、cc-switch、all" ;;
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
  IFS= read -r selection </dev/tty || fatal "无法读取选择"
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
    emit INFO "未检测到交互终端，使用兼容默认选择: Claude Code + CC Switch"
  fi
  parse_selection "$selection"
  remove_skipped_components
  [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]] || fatal "没有可安装组件，请使用 --install 选择至少一项"
  TOTAL_STEPS=$((${#SELECTED_COMPONENTS[@]} * 4))
}

progress_bar_text() {
  local percent="$1" width=28 filled empty bar="" i
  filled=$((percent * width / 100))
  empty=$((width - filled))
  i=0
  while [[ $i -lt $filled ]]; do bar="${bar}#"; i=$((i + 1)); done
  i=0
  while [[ $i -lt $empty ]]; do bar="${bar}-"; i=$((i + 1)); done
  printf '[%s] %3d%%' "$bar" "$percent"
}

render_progress() {
  local status="$1" detail="$2" percent=100 line
  if [[ $TOTAL_STEPS -gt 0 ]]; then
    percent=$((COMPLETED_STEPS * 100 / TOTAL_STEPS))
  fi
  line="$(progress_bar_text "$percent") ${status} ${CURRENT_COMPONENT} / ${CURRENT_STAGE}"
  [[ -n "$detail" ]] && line="${line} - ${detail}"
  log_write PROGRESS "$line"
  [[ $QUIET -eq 1 ]] && return 0
  if is_interactive_output; then
    printf '\r\033[2K%s' "$line" >&2
    printf '\n' >&2
  else
    printf '[PROGRESS] %s\n' "$line" >&2
  fi
}

stage_begin() {
  CURRENT_STAGE="$1"
  CURRENT_COMPONENT_STAGE=$((CURRENT_COMPONENT_STAGE + 1))
  emit STEP "${CURRENT_COMPONENT} · ${CURRENT_STAGE}: ${2:-处理中}"
}

stage_ok() {
  COMPLETED_STEPS=$((COMPLETED_STEPS + 1))
  render_progress "OK" "${1:-完成}"
}

stage_warn() {
  COMPLETED_STEPS=$((COMPLETED_STEPS + 1))
  render_progress "WARN" "${1:-需要重新打开终端确认}"
}

stage_fail() {
  local code="$1" detail="$2"
  LAST_FAILURE_STAGE="$CURRENT_STAGE"
  LAST_FAILURE_DETAIL="$detail"
  COMPLETED_STEPS=$((COMPLETED_STEPS + 1))
  render_progress "FAIL" "${detail}（退出码 ${code}）"
  while [[ $CURRENT_COMPONENT_STAGE -lt 4 ]]; do
    CURRENT_COMPONENT_STAGE=$((CURRENT_COMPONENT_STAGE + 1))
    COMPLETED_STEPS=$((COMPLETED_STEPS + 1))
    CURRENT_STAGE="后续阶段"
    render_progress "SKIP" "因前序失败跳过"
  done
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
  local url="$1" dest="$2" purpose="${3:-file}" status
  emit INFO "下载（${purpose}）: ${url}"
  if [[ $DRY_RUN -eq 1 ]]; then
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    if is_interactive_output; then
      set +e
      curl --fail --location --progress-bar --retry 4 --retry-delay 2 \
        --connect-timeout 15 --max-time 900 --user-agent "ai-cli-installer/${PROGRAM_VERSION}" \
        -o "$dest" "$url" 2> >(tee -a "${LOG_FILE:-/dev/null}" >&2)
      status=$?
      set -e
      return "$status"
    fi
    curl --fail --location --silent --show-error --retry 4 --retry-delay 2 \
      --connect-timeout 15 --max-time 900 --user-agent "ai-cli-installer/${PROGRAM_VERSION}" \
      -o "$dest" "$url"
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    if is_interactive_output; then
      wget --tries=4 --timeout=30 --show-progress --user-agent="ai-cli-installer/${PROGRAM_VERSION}" -O "$dest" "$url"
    else
      wget --tries=4 --timeout=30 --quiet --user-agent="ai-cli-installer/${PROGRAM_VERSION}" -O "$dest" "$url"
    fi
    return $?
  fi
  emit ERROR "需要 curl 或 wget 才能下载文件"
  return 127
}

network_check_url() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    if ! curl --head --location --silent --show-error --connect-timeout 8 --max-time 20 "$url" >/dev/null; then
      emit WARN "无法访问 ${url}；可使用 --proxy，GitHub 下载还可使用 --github-proxy"
    fi
  fi
}

network_check() {
  [[ $SKIP_NETWORK_CHECK -eq 1 || $DRY_RUN -eq 1 ]] && return 0
  emit INFO "检查所选组件的网络连通性"
  contains_component claude && network_check_url "https://claude.ai"
  contains_component codex && network_check_url "https://chatgpt.com"
  contains_component hermes && network_check_url "https://hermes-agent.nousresearch.com"
  contains_component cc-switch && network_check_url "https://api.github.com"
  return 0
}

detect_os() {
  if [[ -n "${INSTALLER_TEST_OS:-}" ]]; then printf '%s' "$INSTALLER_TEST_OS"; return; fi
  case "$(uname -s)" in
    Darwin) printf 'macos' ;;
    Linux) printf 'linux' ;;
    *) fatal "不支持的系统: $(uname -s)。Windows 请运行 install.ps1" ;;
  esac
}

detect_arch() {
  local machine="${INSTALLER_TEST_ARCH:-$(uname -m)}"
  case "$machine" in
    x86_64|amd64|AMD64) printf 'x86_64' ;;
    arm64|aarch64|ARM64) printf 'arm64' ;;
    *) fatal "不支持的 CPU 架构: ${machine}" ;;
  esac
}

detect_distro() {
  if [[ -n "${INSTALLER_TEST_DISTRO:-}" ]]; then printf '%s' "$INSTALLER_TEST_DISTRO"; return; fi
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
    TMP_DIR="${TMPDIR:-/tmp}/ai-cli-installer-dry-run-$$"
  else
    TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t ai-cli-installer)"
  fi
}

maybe_fail_component() {
  local component="$1"
  if [[ "${INSTALLER_TEST_FAIL_COMPONENT:-}" == "$component" ]]; then
    emit ERROR "测试注入失败: $(component_label "$component")"
    return 97
  fi
  return 0
}

verify_command() {
  local command_name="$1"
  if [[ $DRY_RUN -eq 1 ]]; then
    stage_ok "dry-run：计划验证 ${command_name}"
    return 0
  fi
  if command -v "$command_name" >/dev/null 2>&1; then
    "$command_name" --version 2>&1 | head -n 1 | while IFS= read -r line; do log_write INFO "$line"; done
    stage_ok "已检测到 ${command_name}"
  else
    stage_warn "当前终端尚未找到 ${command_name}，请重新打开终端后检查"
  fi
}

install_script_component() {
  local component="$1" label="$2" url="$3" shell_name="$4" verify_name="$5" installer status
  shift 5
  installer="${TMP_DIR}/${component}-install.sh"

  stage_begin "准备" "确认官方安装源"
  if maybe_fail_component "$component"; then :; else status=$?; stage_fail "$status" "准备阶段被中止"; return "$status"; fi
  stage_ok "官方源: ${url}"

  stage_begin "下载" "获取官方安装器"
  if download "$url" "$installer" "installer"; then :; else status=$?; stage_fail "$status" "下载安装器失败"; return "$status"; fi
  stage_ok "安装器已准备"

  stage_begin "安装" "运行官方安装器"
  if [[ $DRY_RUN -eq 1 ]]; then
    emit INFO "计划执行: ${shell_name} ${installer} $*"
    stage_ok "dry-run：未修改系统"
  else
    chmod 700 "$installer"
    if "$shell_name" "$installer" "$@"; then :; else status=$?; stage_fail "$status" "官方安装器执行失败"; return "$status"; fi
    stage_ok "官方安装器执行完成"
  fi

  stage_begin "验证" "检查 ${verify_name} 命令"
  verify_command "$verify_name"
  return 0
}

release_asset_url() {
  local pattern="$1" json url=""
  if [[ -n "${INSTALLER_FAKE_ASSET_URL:-}" ]]; then printf '%s' "$INSTALLER_FAKE_ASSET_URL"; return; fi
  if [[ $DRY_RUN -eq 1 ]]; then
    case "$pattern" in
      *macOS*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-macOS.zip' "$CC_SWITCH_REPO" ;;
      *Linux-x86_64*deb*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-x86_64.deb' "$CC_SWITCH_REPO" ;;
      *Linux-x86_64*rpm*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-x86_64.rpm' "$CC_SWITCH_REPO" ;;
      *Linux-x86_64*AppImage*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-x86_64.AppImage' "$CC_SWITCH_REPO" ;;
      *Linux-arm64*deb*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-arm64.deb' "$CC_SWITCH_REPO" ;;
      *Linux-arm64*rpm*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-arm64.rpm' "$CC_SWITCH_REPO" ;;
      *) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-package' "$CC_SWITCH_REPO" ;;
    esac
    return
  fi
  json="${TMP_DIR}/cc-switch-release.json"
  download "$GITHUB_API_URL" "$json" "metadata" >&2
  if command -v python3 >/dev/null 2>&1; then
    url="$(python3 - "$json" "$pattern" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
rx = re.compile(sys.argv[2], re.I)
for asset in release.get("assets", []):
    if rx.search(asset.get("name", "")):
        print(asset.get("browser_download_url", ""))
        break
PY
)"
  else
    url="$(grep -E '"browser_download_url"' "$json" | sed -E 's/.*"(https:[^"]+)".*/\1/' | grep -Ei "$pattern" | head -n 1 || true)"
  fi
  [[ -n "$url" ]] || return 44
  case "$url" in
    https://github.com/*|https://objects.githubusercontent.com/*|https://github-releases.githubusercontent.com/*) ;;
    *) return 45 ;;
  esac
  printf '%s' "$url"
}

install_cc_switch() {
  local os_name="$1" arch="$2" distro="$3" ext pattern url asset target applications extract app status
  stage_begin "准备" "检测安装包格式并读取官方 Release"
  if maybe_fail_component cc-switch; then :; else status=$?; stage_fail "$status" "准备阶段被中止"; return "$status"; fi

  if [[ "$os_name" == "macos" && -x "$(command -v brew 2>/dev/null || true)" ]]; then
    ext="brew"
    url="Homebrew cask cc-switch"
  elif [[ "$os_name" == "macos" ]]; then
    ext="zip"
    pattern='CC-Switch-v.*-macOS\.zip$'
    if url="$(release_asset_url "$pattern")"; then :; else status=$?; stage_fail "$status" "无法解析 macOS Release"; return "$status"; fi
  else
    case "$distro" in
      ubuntu|debian|linuxmint|pop|kali|zorin) ext="deb" ;;
      fedora|rhel|centos|rocky|almalinux|ol|opensuse*|sles) ext="rpm" ;;
      *) ext="AppImage" ;;
    esac
    pattern="CC-Switch-v.*-Linux-${arch}\.${ext}$"
    if url="$(release_asset_url "$pattern")"; then :; else status=$?; stage_fail "$status" "无法解析 Linux Release"; return "$status"; fi
  fi
  stage_ok "安装方式: ${ext}；来源: ${url}"

  stage_begin "下载" "获取 CC Switch 安装包"
  if [[ "$ext" == "brew" ]]; then
    stage_ok "由 Homebrew 管理下载"
  else
    asset="${TMP_DIR}/$(basename "$url")"
    if download "$(apply_github_proxy "$url")" "$asset" "package"; then :; else status=$?; stage_fail "$status" "下载安装包失败"; return "$status"; fi
    stage_ok "安装包已准备: $(basename "$asset")"
  fi

  stage_begin "安装" "安装 CC Switch"
  case "$ext" in
    brew)
      if run_cmd brew install --cask cc-switch; then :; else status=$?; stage_fail "$status" "Homebrew 安装失败"; return "$status"; fi
      ;;
    zip)
      if [[ $DRY_RUN -eq 1 ]]; then
        emit INFO "计划解压 ${asset} 并复制应用"
      else
        command -v unzip >/dev/null 2>&1 || { stage_fail 127 "缺少 unzip"; return 127; }
        extract="${TMP_DIR}/cc-switch-macos"
        mkdir -p "$extract"
        if unzip -q "$asset" -d "$extract"; then :; else status=$?; stage_fail "$status" "解压失败"; return "$status"; fi
        app="$(find "$extract" -type d -name '*.app' -print | head -n 1)"
        [[ -n "$app" ]] || { stage_fail 46 "ZIP 中未找到 .app"; return 46; }
        applications="${INSTALLER_TEST_APPLICATIONS_DIR:-/Applications}"
        target="${applications}/$(basename "$app")"
        if [[ -w "$applications" || ! -e "$applications" ]]; then
          mkdir -p "$applications"
          run_cmd ditto "$app" "$target" || { status=$?; stage_fail "$status" "复制应用失败"; return "$status"; }
        else
          as_root ditto "$app" "$target" || { status=$?; stage_fail "$status" "复制应用失败"; return "$status"; }
        fi
      fi
      ;;
    deb)
      if command -v apt >/dev/null 2>&1; then as_root apt install -y "$asset" || { status=$?; stage_fail "$status" "APT 安装失败"; return "$status"; }
      else as_root dpkg -i "$asset" || { status=$?; stage_fail "$status" "DPKG 安装失败"; return "$status"; }; fi
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then as_root dnf install -y "$asset" || { status=$?; stage_fail "$status" "DNF 安装失败"; return "$status"; }
      elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install "$asset" || { status=$?; stage_fail "$status" "Zypper 安装失败"; return "$status"; }
      elif command -v yum >/dev/null 2>&1; then as_root yum install -y "$asset" || { status=$?; stage_fail "$status" "YUM 安装失败"; return "$status"; }
      else as_root rpm -Uvh "$asset" || { status=$?; stage_fail "$status" "RPM 安装失败"; return "$status"; }; fi
      ;;
    AppImage)
      target="${HOME}/.local/bin/cc-switch.AppImage"
      run_cmd mkdir -p "${HOME}/.local/bin" "${HOME}/.local/share/applications" || return $?
      run_cmd cp "$asset" "$target" || { status=$?; stage_fail "$status" "复制 AppImage 失败"; return "$status"; }
      run_cmd chmod +x "$target" || { status=$?; stage_fail "$status" "设置 AppImage 权限失败"; return "$status"; }
      if [[ $DRY_RUN -eq 0 ]]; then
        cat > "${HOME}/.local/share/applications/cc-switch.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CC Switch
Exec=${target}
Terminal=false
Categories=Development;
EOF
      fi
      ;;
  esac
  stage_ok "CC Switch 安装步骤完成"

  stage_begin "验证" "检查桌面应用或安装文件"
  if [[ $DRY_RUN -eq 1 ]]; then
    stage_ok "dry-run：计划验证安装结果"
  elif [[ "$ext" == "AppImage" && -x "$target" ]]; then
    stage_ok "AppImage 已安装到 ${target}"
  else
    stage_warn "安装命令已成功；请从应用菜单启动 CC Switch"
  fi
  return 0
}

install_component() {
  local component="$1" os_name="$2" arch="$3" distro="$4"
  case "$component" in
    claude) install_script_component claude "Claude Code" "$CLAUDE_INSTALL_URL" bash claude "$CHANNEL" ;;
    codex) install_script_component codex "Codex CLI" "$CODEX_INSTALL_URL" sh codex ;;
    hermes) install_script_component hermes "Hermes Agent" "$HERMES_INSTALL_URL" bash hermes ;;
    cc-switch) install_cc_switch "$os_name" "$arch" "$distro" ;;
    *) return 64 ;;
  esac
}

run_component() {
  local component="$1" os_name="$2" arch="$3" distro="$4" label status
  label="$(component_label "$component")"
  CURRENT_COMPONENT="$label"
  CURRENT_STAGE=""
  CURRENT_COMPONENT_STAGE=0
  LAST_FAILURE_STAGE=""
  LAST_FAILURE_DETAIL=""
  emit INFO "========== ${label} =========="
  if install_component "$component" "$os_name" "$arch" "$distro"; then
    SUCCEEDED_COMPONENTS+=("$label")
    emit OK "${label}: 成功"
  else
    status=$?
    FAILED_COMPONENTS+=("$label")
    FAILED_DETAILS+=("${label}: 失败阶段=${LAST_FAILURE_STAGE:-未知}，退出码=${status}，原因=${LAST_FAILURE_DETAIL:-未提供}")
    emit WARN "${label}: 失败阶段 ${LAST_FAILURE_STAGE:-未知}（退出码 ${status}），继续处理其他组件"
  fi
}

join_by_comma() {
  local first=1 item
  for item in "$@"; do
    [[ $first -eq 1 ]] || printf ', '
    printf '%s' "$item"
    first=0
  done
}

print_summary() {
  local elapsed detail
  elapsed="$SECONDS"
  emit SUMMARY "========== 安装汇总 =========="
  if [[ ${#SUCCEEDED_COMPONENTS[@]} -gt 0 ]]; then emit SUMMARY "成功: $(join_by_comma "${SUCCEEDED_COMPONENTS[@]}")"; fi
  if [[ ${#SKIPPED_COMPONENTS[@]} -gt 0 ]]; then emit SUMMARY "跳过: $(join_by_comma "${SKIPPED_COMPONENTS[@]}")"; fi
  if [[ ${#FAILED_COMPONENTS[@]} -gt 0 ]]; then
    emit SUMMARY "失败: $(join_by_comma "${FAILED_COMPONENTS[@]}")"
    for detail in "${FAILED_DETAILS[@]}"; do emit SUMMARY "$detail"; done
  fi
  emit SUMMARY "耗时: ${elapsed} 秒"
  if [[ $LOG_ENABLED -eq 1 ]]; then emit SUMMARY "详细日志: ${LOG_FILE}"; fi
}

main() {
  local os_name arch distro item selected_labels=""
  START_EPOCH="$(date +%s)"
  RUN_STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
  SECONDS=0
  init_log
  emit INFO "${PROGRAM_NAME} v${PROGRAM_VERSION}"
  emit INFO "说明：只使用各项目官方安装源，不绕过地区、账号或服务条款限制。"
  [[ -n "$PROXY_URL" ]] && emit INFO "当前进程代理: ${PROXY_URL}"
  [[ $LOG_ENABLED -eq 1 ]] && emit INFO "详细日志: ${LOG_FILE}"

  resolve_selection
  make_temp_dir
  os_name="$(detect_os)"
  arch="$(detect_arch)"
  distro="unknown"
  [[ "$os_name" == "linux" ]] && distro="$(detect_distro)"
  for item in "${SELECTED_COMPONENTS[@]}"; do
    if [[ -n "$selected_labels" ]]; then selected_labels="${selected_labels}, "; fi
    selected_labels="${selected_labels}$(component_label "$item")"
  done
  emit INFO "检测到: OS=${os_name} ARCH=${arch} DISTRO=${distro}"
  emit INFO "已选择: ${selected_labels}"
  network_check
  for item in "${SELECTED_COMPONENTS[@]}"; do
    run_component "$item" "$os_name" "$arch" "$distro"
  done
  print_summary
  [[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]
}

main "$@"
