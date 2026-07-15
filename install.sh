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
SKIP_CLAUDE=0
SKIP_CODEX=0
SKIP_HERMES=0
SKIP_CC_SWITCH=0
DRY_RUN=0
NON_INTERACTIVE=0
SKIP_NETWORK_CHECK=0
QUIET=0
NO_PROGRESS=0
DEBUG_MODE=0
KEEP_TEMP=0
TMP_DIR=""
LOG_READY=0
TTY_PROGRESS=0
PROGRESS_ACTIVE=0
PROGRESS_CURRENT=0
PROGRESS_TOTAL=1
START_EPOCH=0
CURRENT_PHASE=""
CC_SWITCH_ASSET_URL=""
CC_SWITCH_PACKAGE_KIND=""
CC_SWITCH_ASSET_PATH=""

SELECTED_COMPONENTS=()
SKIPPED_COMPONENTS=()
RESULT_COMPONENTS=()
RESULT_STATUSES=()
RESULT_DURATIONS=()
RESULT_DETAILS=()

raw_die() { printf '[ERROR] %s\n' "$*" >&2; exit 2; }

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
  --proxy URL               仅为当前安装进程设置 HTTP/HTTPS 代理
  --github-proxy URL        为 GitHub Release 下载添加用户指定前缀
  --skip-claude             从选择中移除 Claude Code
  --skip-codex              从选择中移除 Codex
  --skip-hermes             从选择中移除 Hermes
  --skip-cc-switch          从选择中移除 CC Switch
  --dry-run                 展示完整流程，不下载或修改系统
  --non-interactive         禁用菜单；未选择时默认 Claude Code + CC Switch
  --skip-network-check      跳过安装前网络诊断
  --quiet                   终端静默，完整内容仍写入日志
  --no-progress             禁用动态进度条，保留逐行阶段信息
  --log-file PATH           指定日志文件路径
  --debug                   写入额外诊断信息（不会记录密钥）
  --keep-temp               保留临时目录，便于排错
  -h, --help                显示帮助

示例:
  ./install.sh
  ./install.sh --install all
  ./install.sh --install codex,hermes --log-file ~/installer.log
  ./install.sh --install cc-switch --no-progress
  ./install.sh --install all --dry-run --skip-network-check
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) [[ $# -ge 2 ]] || raw_die "--install 缺少组件列表"; RAW_SELECTION="$2"; shift 2 ;;
    --channel) [[ $# -ge 2 ]] || raw_die "--channel 缺少参数"; CHANNEL="$2"; shift 2 ;;
    --proxy) [[ $# -ge 2 ]] || raw_die "--proxy 缺少 URL"; PROXY_URL="$2"; shift 2 ;;
    --github-proxy) [[ $# -ge 2 ]] || raw_die "--github-proxy 缺少 URL"; GITHUB_PROXY="$2"; shift 2 ;;
    --log-file|--log) [[ $# -ge 2 ]] || raw_die "--log-file 缺少路径"; LOG_FILE="$2"; shift 2 ;;
    --skip-claude) SKIP_CLAUDE=1; shift ;;
    --skip-codex) SKIP_CODEX=1; shift ;;
    --skip-hermes) SKIP_HERMES=1; shift ;;
    --skip-cc-switch) SKIP_CC_SWITCH=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --skip-network-check) SKIP_NETWORK_CHECK=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --no-progress) NO_PROGRESS=1; shift ;;
    --debug) DEBUG_MODE=1; shift ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) raw_die "未知参数: $1（使用 --help 查看帮助）" ;;
  esac
done

[[ "$CHANNEL" == "stable" || "$CHANNEL" == "latest" ]] || raw_die "--channel 只支持 stable 或 latest"

if [[ -n "$PROXY_URL" ]]; then
  export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL"
  export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL"
fi
if [[ $NON_INTERACTIVE -eq 1 ]]; then
  export CI=1
  export DEBIAN_FRONTEND=noninteractive
fi

now_iso() { date '+%Y-%m-%dT%H:%M:%S%z'; }
now_epoch() { date '+%s'; }

init_log() {
  local log_dir parent
  if [[ -z "$LOG_FILE" ]]; then
    log_dir="${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/ai-cli-installer/logs"
    LOG_FILE="$log_dir/$(date '+%Y%m%d-%H%M%S').log"
  fi
  parent="$(dirname "$LOG_FILE")"
  mkdir -p "$parent" 2>/dev/null || {
    LOG_FILE="${TMPDIR:-/tmp}/ai-cli-installer-$(date '+%Y%m%d-%H%M%S').log"
    mkdir -p "$(dirname "$LOG_FILE")"
  }
  : >"$LOG_FILE"
  chmod 600 "$LOG_FILE" 2>/dev/null || true
  LOG_READY=1
}

finish_progress_line() {
  if [[ $PROGRESS_ACTIVE -eq 1 ]]; then
    printf '\n'
    PROGRESS_ACTIVE=0
  fi
}

redact_text() {
  printf '%s' "$*" | sed -E \
    -e 's#(https?://)[^/@[:space:]]+@#\1***@#g' \
    -e 's#([Aa]uthorization:[[:space:]]*(Bearer|Basic))[[:space:]]+[^[:space:]]+#\1 ***#g' \
    -e 's#((ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|NOUS_API_KEY)=)[^[:space:]]+#\1[REDACTED]#g'
}

redact_stream() {
  sed -E \
    -e 's#(https?://)[^/@[:space:]]+@#\1***@#g' \
    -e 's#([Aa]uthorization:[[:space:]]*(Bearer|Basic))[[:space:]]+[^[:space:]]+#\1 ***#g' \
    -e 's#((ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|NOUS_API_KEY)=)[^[:space:]]+#\1[REDACTED]#g'
}

write_log() {
  local level="$1"; shift
  local clean
  [[ $LOG_READY -eq 1 ]] || return 0
  clean="$(redact_text "$*")"
  printf '%s [%s] %s\n' "$(now_iso)" "$level" "$clean" >>"$LOG_FILE"
}

emit() {
  local level="$1"; shift
  local message
  message="$(redact_text "$*")"
  write_log "$level" "$message"
  [[ $QUIET -eq 1 ]] && return 0
  finish_progress_line
  case "$level" in
    INFO) printf '[INFO] %s\n' "$message" ;;
    OK) printf '[ OK ] %s\n' "$message" ;;
    WARN) printf '[WARN] %s\n' "$message" >&2 ;;
    ERROR) printf '[ERROR] %s\n' "$message" >&2 ;;
    DEBUG) [[ $DEBUG_MODE -eq 1 ]] && printf '[DEBUG] %s\n' "$message" ;;
    *) printf '[%s] %s\n' "$level" "$message" ;;
  esac
}

log() { emit INFO "$*"; }
ok() { emit OK "$*"; }
warn() { emit WARN "$*"; }
debug() { if [[ $DEBUG_MODE -eq 1 ]]; then emit DEBUG "$*"; else write_log DEBUG "$*"; fi; }
die() { emit ERROR "$*"; exit 1; }

redact_url() {
  printf '%s' "$1" | sed -E 's#(https?://)[^/@]+@#\1***@#'
}

render_bar() {
  local percent="$1" width=24 filled empty bar="" i
  filled=$((percent * width / 100))
  empty=$((width - filled))
  i=0
  while [[ $i -lt $filled ]]; do bar="${bar}#"; i=$((i + 1)); done
  i=0
  while [[ $i -lt $empty ]]; do bar="${bar}-"; i=$((i + 1)); done
  printf '%s' "$bar"
}

progress_advance() {
  local label="$1" percent bar
  PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
  [[ $PROGRESS_CURRENT -gt $PROGRESS_TOTAL ]] && PROGRESS_CURRENT=$PROGRESS_TOTAL
  percent=$((PROGRESS_CURRENT * 100 / PROGRESS_TOTAL))
  write_log STEP "${PROGRESS_CURRENT}/${PROGRESS_TOTAL} ${percent}% ${label}"
  [[ $QUIET -eq 1 ]] && return 0
  if [[ $TTY_PROGRESS -eq 1 ]]; then
    bar="$(render_bar "$percent")"
    printf '\r[%s] %3d%% (%d/%d) %s' "$bar" "$percent" "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$label"
    PROGRESS_ACTIVE=1
  else
    printf '[STEP %d/%d] %3d%% %s\n' "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$percent" "$label"
  fi
}

phase() {
  local component="$1" phase_name="$2" detail="$3"
  CURRENT_PHASE="$phase_name"
  progress_advance "${component} · ${phase_name} · ${detail}"
}

print_banner() {
  [[ $QUIET -eq 1 ]] && return 0
  cat <<EOF
============================================================
  ${PROGRAM_NAME} v${PROGRAM_VERSION}
  Claude Code / Codex / Hermes / CC Switch
============================================================
EOF
}

quote_cmd() {
  local out="" arg
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    out="${out}${arg} "
  done
  printf '%s' "${out% }"
}

run_logged() {
  local cmd_text status
  cmd_text="$(quote_cmd "$@")"
  write_log CMD "$cmd_text"
  debug "执行命令: ${cmd_text}"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "Dry-run 执行: ${cmd_text}"
    return 0
  fi
  set +e
  if [[ $QUIET -eq 1 ]]; then
    "$@" > >(redact_stream >>"$LOG_FILE") 2> >(redact_stream >>"$LOG_FILE")
    status=$?
  else
    "$@" > >(redact_stream | tee -a "$LOG_FILE") 2> >(redact_stream | tee -a "$LOG_FILE" >&2)
    status=$?
  fi
  set -e
  return "$status"
}

as_root() {
  if [[ $(id -u) -eq 0 ]]; then
    run_logged "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run_logged sudo "$@"
  else
    warn "安装系统软件需要 root 权限，但未找到 sudo"
    return 1
  fi
}

cleanup() {
  finish_progress_line
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    if [[ $KEEP_TEMP -eq 1 ]]; then
      write_log INFO "保留临时目录: ${TMP_DIR}"
      [[ $QUIET -eq 1 ]] || printf '[INFO] 临时目录已保留: %s\n' "$TMP_DIR"
    else
      rm -rf "$TMP_DIR"
    fi
  fi
}
trap cleanup EXIT

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
  contains_component "$component" || SELECTED_COMPONENTS+=("$component")
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
  old_ifs="$IFS"; IFS=','
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
  IFS= read -r selection </dev/tty || raw_die "无法读取选择"
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
  if [[ ${#filtered[@]} -eq 0 ]]; then SELECTED_COMPONENTS=(); else SELECTED_COMPONENTS=("${filtered[@]}"); fi
}

resolve_selection() {
  local selection="$RAW_SELECTION"
  if [[ -z "$selection" && -n "${INSTALLER_TEST_SELECTION:-}" ]]; then
    selection="$INSTALLER_TEST_SELECTION"
  elif [[ -z "$selection" && $NON_INTERACTIVE -eq 0 ]] && has_interactive_tty; then
    selection="$(show_menu_and_read_selection)"
  elif [[ -z "$selection" ]]; then
    selection="claude,cc-switch"
  fi
  parse_selection "$selection"
  remove_skipped_components
  [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]] || raw_die "没有可安装组件，请使用 --install 选择至少一项"
}

join_by_comma() {
  local first=1 item
  for item in "$@"; do
    [[ $first -eq 0 ]] && printf ', '
    printf '%s' "$item"
    first=0
  done
}

detect_os() {
  if [[ -n "${INSTALLER_TEST_OS:-}" ]]; then printf '%s' "$INSTALLER_TEST_OS"; return; fi
  case "$(uname -s)" in
    Darwin) printf 'macos' ;;
    Linux) printf 'linux' ;;
    *) die "不支持的系统: $(uname -s)。Windows 请运行 install.ps1" ;;
  esac
}

detect_arch() {
  local machine="${INSTALLER_TEST_ARCH:-$(uname -m)}"
  case "$machine" in
    x86_64|amd64|AMD64) printf 'x86_64' ;;
    arm64|aarch64|ARM64) printf 'arm64' ;;
    *) die "不支持的 CPU 架构: ${machine}" ;;
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
  TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t ai-cli-installer)"
}

validate_https_url() {
  case "$1" in https://*) return 0 ;; *) warn "拒绝非 HTTPS 下载地址: $1"; return 1 ;; esac
}

apply_github_proxy() {
  local url="$1"
  if [[ -z "$GITHUB_PROXY" ]]; then printf '%s' "$url"; else printf '%s%s' "${GITHUB_PROXY%/}/" "$url"; fi
}

validate_file() {
  local path="$1" kind="$2"
  [[ $DRY_RUN -eq 1 ]] && return 0
  [[ -s "$path" ]] || { warn "下载文件为空或不存在: ${path}"; return 1; }
  if [[ "$kind" == "script" ]]; then
    head -c 256 "$path" | grep -Eq '(#!|powershell|bash|sh)' || {
      warn "下载内容不像安装脚本: ${path}"
      return 1
    }
  fi
}

fingerprint_file() {
  local path="$1" hash=""
  [[ $DRY_RUN -eq 1 ]] && { log "Dry-run 跳过本地 SHA-256 指纹计算"; return 0; }
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$path" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(shasum -a 256 "$path" | awk '{print $1}')"
  fi
  [[ -n "$hash" ]] && log "本地 SHA-256: ${hash}" || debug "未找到 SHA-256 工具"
}

download_file() {
  local url="$1" dest="$2" resume="${3:-0}" kind="${4:-file}" status
  validate_https_url "$url" || return 1
  log "下载地址: ${url}"
  write_log INFO "下载目标: ${dest}"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "Dry-run 下载: ${url} -> ${dest}"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if command -v curl >/dev/null 2>&1; then
    local curl_args=(--fail --location --retry 4 --retry-all-errors --retry-delay 2 --connect-timeout 15 --max-time 1800 --user-agent "ai-cli-installer/${PROGRAM_VERSION}")
    [[ "$resume" == "1" ]] && curl_args+=(--continue-at -)
    if [[ $TTY_PROGRESS -eq 1 ]]; then curl_args+=(--progress-bar); else curl_args+=(--silent --show-error); fi
    set +e
    if [[ $QUIET -eq 1 ]]; then
      curl "${curl_args[@]}" -o "$dest" "$url" >>"$LOG_FILE" 2>&1
      status=$?
    else
      curl "${curl_args[@]}" -o "$dest" "$url" > >(redact_stream | tee -a "$LOG_FILE") 2> >(redact_stream | tee -a "$LOG_FILE" >&2)
      status=$?
    fi
    set -e
  elif command -v wget >/dev/null 2>&1; then
    local wget_args=(--tries=4 --timeout=30 --user-agent="ai-cli-installer/${PROGRAM_VERSION}")
    [[ "$resume" == "1" ]] && wget_args+=(--continue)
    [[ $TTY_PROGRESS -eq 0 ]] && wget_args+=(--quiet)
    set +e
    if [[ $QUIET -eq 1 ]]; then
      wget "${wget_args[@]}" -O "$dest" "$url" >>"$LOG_FILE" 2>&1
      status=$?
    else
      wget "${wget_args[@]}" -O "$dest" "$url" > >(redact_stream | tee -a "$LOG_FILE") 2> >(redact_stream | tee -a "$LOG_FILE" >&2)
      status=$?
    fi
    set -e
  else
    warn "需要 curl 或 wget 才能下载文件"
    return 1
  fi
  [[ $status -eq 0 ]] || { warn "下载失败，退出码 ${status}: ${url}"; return "$status"; }
  validate_file "$dest" "$kind" || return 1
  fingerprint_file "$dest"
}

network_check_url() {
  local label="$1" url="$2" status=0
  if command -v curl >/dev/null 2>&1; then
    set +e
    curl --head --location --silent --show-error --retry 2 --connect-timeout 8 --max-time 20 "$url" >/dev/null 2>>"$LOG_FILE"
    status=$?
    set -e
    if [[ $status -eq 0 ]]; then ok "网络可达: ${label}"; else warn "网络不可达: ${label}（${url}）"; fi
  else
    debug "未找到 curl，跳过 ${label} 网络预检"
  fi
  return 0
}

network_check() {
  if [[ $SKIP_NETWORK_CHECK -eq 1 || $DRY_RUN -eq 1 ]]; then
    log "已跳过网络预检"
    return 0
  fi
  contains_component claude && network_check_url "Claude" "https://claude.ai"
  contains_component codex && network_check_url "Codex" "https://chatgpt.com"
  contains_component hermes && network_check_url "Hermes" "https://hermes-agent.nousresearch.com"
  contains_component cc-switch && network_check_url "GitHub API" "https://api.github.com"
  return 0
}

maybe_fail_component() {
  local component="$1"
  if [[ "${INSTALLER_TEST_FAIL_COMPONENT:-}" == "$component" ]]; then
    warn "测试注入失败: $(component_label "$component")"
    return 97
  fi
}

verify_cli() {
  local command_name="$1" label="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    log "验证命令: ${command_name}"
    run_logged "$command_name" --version || true
  elif [[ -x "${HOME:-}/.local/bin/${command_name}" || -x "${HOME:-}/.hermes/bin/${command_name}" ]]; then
    ok "${label} 已安装，重新打开终端后 PATH 生效"
  else
    warn "当前 Shell 暂未找到 ${command_name}；官方安装器已完成，请重新打开终端后验证"
  fi
  return 0
}

install_claude() {
  local label="Claude Code" installer="$TMP_DIR/claude-install.sh"
  phase "$label" "准备" "确认 Anthropic 官方源与通道 ${CHANNEL}"
  maybe_fail_component claude || return $?
  phase "$label" "下载" "获取官方安装脚本"
  download_file "$CLAUDE_INSTALL_URL" "$installer" 0 script || return $?
  phase "$label" "安装" "执行官方安装器"
  [[ $DRY_RUN -eq 1 ]] || chmod 700 "$installer"
  run_logged bash "$installer" "$CHANNEL" || return $?
  phase "$label" "验证" "检查 claude 命令"
  [[ $DRY_RUN -eq 1 ]] || verify_cli claude "$label"
}

install_codex() {
  local label="Codex CLI" installer="$TMP_DIR/codex-install.sh"
  phase "$label" "准备" "确认 OpenAI 官方源"
  maybe_fail_component codex || return $?
  phase "$label" "下载" "获取官方安装脚本"
  download_file "$CODEX_INSTALL_URL" "$installer" 0 script || return $?
  phase "$label" "安装" "执行官方安装器"
  [[ $DRY_RUN -eq 1 ]] || chmod 700 "$installer"
  run_logged sh "$installer" || return $?
  phase "$label" "验证" "检查 codex 命令"
  [[ $DRY_RUN -eq 1 ]] || verify_cli codex "$label"
}

install_hermes() {
  local label="Hermes Agent" installer="$TMP_DIR/hermes-install.sh"
  phase "$label" "准备" "确认 Nous Research 官方源"
  maybe_fail_component hermes || return $?
  phase "$label" "下载" "获取官方安装脚本"
  download_file "$HERMES_INSTALL_URL" "$installer" 0 script || return $?
  phase "$label" "安装" "执行官方安装器"
  [[ $DRY_RUN -eq 1 ]] || chmod 700 "$installer"
  run_logged bash "$installer" || return $?
  phase "$label" "验证" "检查 hermes 命令"
  [[ $DRY_RUN -eq 1 ]] || verify_cli hermes "$label"
}

select_cc_switch_kind() {
  local os="$1" distro="$2"
  if [[ "$os" == "macos" ]]; then
    if command -v brew >/dev/null 2>&1; then CC_SWITCH_PACKAGE_KIND="brew"; else CC_SWITCH_PACKAGE_KIND="zip"; fi
    return
  fi
  case "$distro" in
    ubuntu|debian|linuxmint|pop|kali|zorin) CC_SWITCH_PACKAGE_KIND="deb" ;;
    fedora|rhel|centos|rocky|almalinux|ol|opensuse*|sles) CC_SWITCH_PACKAGE_KIND="rpm" ;;
    *) CC_SWITCH_PACKAGE_KIND="AppImage" ;;
  esac
}

resolve_cc_switch_asset() {
  local arch="$1" pattern json url=""
  CC_SWITCH_ASSET_URL=""
  case "$CC_SWITCH_PACKAGE_KIND" in
    brew) return 0 ;;
    zip) pattern='CC-Switch-v.*-macOS\.zip$' ;;
    deb|rpm|AppImage) pattern="CC-Switch-v.*-Linux-${arch}\\.${CC_SWITCH_PACKAGE_KIND}$" ;;
    *) warn "未知 CC Switch 包类型: ${CC_SWITCH_PACKAGE_KIND}"; return 1 ;;
  esac
  if [[ -n "${INSTALLER_FAKE_ASSET_URL:-}" ]]; then
    CC_SWITCH_ASSET_URL="$INSTALLER_FAKE_ASSET_URL"
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    CC_SWITCH_ASSET_URL="https://github.com/${CC_SWITCH_REPO}/releases/latest/download/CC-Switch-LATEST-${arch}.${CC_SWITCH_PACKAGE_KIND}"
    return 0
  fi
  json="$TMP_DIR/cc-switch-release.json"
  download_file "$GITHUB_API_URL" "$json" 0 metadata || return $?
  if command -v python3 >/dev/null 2>&1; then
    url="$(python3 - "$json" "$pattern" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding='utf-8') as f:
    release = json.load(f)
regex = re.compile(sys.argv[2], re.I)
for asset in release.get('assets', []):
    if regex.search(asset.get('name', '')):
        print(asset.get('browser_download_url', ''))
        break
PY
)"
  else
    url="$(grep -E '"browser_download_url"' "$json" | sed -E 's/.*"(https:[^"]+)".*/\1/' | grep -Ei "$pattern" | head -n 1 || true)"
  fi
  [[ -n "$url" ]] || { warn "未找到匹配的 CC Switch 安装包: ${pattern}"; return 1; }
  case "$url" in
    https://github.com/*|https://objects.githubusercontent.com/*|https://github-releases.githubusercontent.com/*) ;;
    *) warn "Release 返回了非 GitHub 下载地址，已拒绝: ${url}"; return 1 ;;
  esac
  CC_SWITCH_ASSET_URL="$url"
}

install_cc_switch_package() {
  local target extract app
  case "$CC_SWITCH_PACKAGE_KIND" in
    brew) run_logged brew install --cask cc-switch ;;
    deb)
      if command -v apt >/dev/null 2>&1; then as_root apt install -y "$CC_SWITCH_ASSET_PATH"; else as_root dpkg -i "$CC_SWITCH_ASSET_PATH"; fi
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then as_root dnf install -y "$CC_SWITCH_ASSET_PATH"
      elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install "$CC_SWITCH_ASSET_PATH"
      elif command -v yum >/dev/null 2>&1; then as_root yum install -y "$CC_SWITCH_ASSET_PATH"
      else as_root rpm -Uvh "$CC_SWITCH_ASSET_PATH"; fi
      ;;
    AppImage)
      target="${HOME:-/tmp}/.local/bin/cc-switch.AppImage"
      run_logged mkdir -p "$(dirname "$target")"
      run_logged cp "$CC_SWITCH_ASSET_PATH" "$target"
      run_logged chmod +x "$target"
      ;;
    zip)
      extract="$TMP_DIR/cc-switch-macos"
      run_logged mkdir -p "$extract"
      run_logged unzip -q "$CC_SWITCH_ASSET_PATH" -d "$extract" || return $?
      if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
      app="$(find "$extract" -type d -name '*.app' -print | head -n 1)"
      [[ -n "$app" ]] || { warn "ZIP 中未找到 .app"; return 1; }
      if [[ -w /Applications ]]; then run_logged ditto "$app" "/Applications/$(basename "$app")"; else as_root ditto "$app" "/Applications/$(basename "$app")"; fi
      ;;
  esac
}

install_cc_switch() {
  local os="$1" arch="$2" distro="$3" label="CC Switch" download_url
  phase "$label" "准备" "识别 ${distro}/${arch} 安装包"
  maybe_fail_component cc-switch || return $?
  select_cc_switch_kind "$os" "$distro"
  resolve_cc_switch_asset "$arch" || return $?
  log "CC Switch 包类型: ${CC_SWITCH_PACKAGE_KIND}"
  if [[ "$CC_SWITCH_PACKAGE_KIND" == "brew" ]]; then
    phase "$label" "下载" "由 Homebrew 管理下载"
    CC_SWITCH_ASSET_PATH=""
  else
    download_url="$(apply_github_proxy "$CC_SWITCH_ASSET_URL")"
    CC_SWITCH_ASSET_PATH="$TMP_DIR/$(basename "$CC_SWITCH_ASSET_URL")"
    phase "$label" "下载" "获取 ${CC_SWITCH_PACKAGE_KIND} 安装包"
    download_file "$download_url" "$CC_SWITCH_ASSET_PATH" 1 package || return $?
  fi
  phase "$label" "安装" "安装 ${CC_SWITCH_PACKAGE_KIND} 包"
  install_cc_switch_package || return $?
  phase "$label" "验证" "确认安装流程完成"
  if [[ "$CC_SWITCH_PACKAGE_KIND" == "AppImage" && $DRY_RUN -eq 0 ]]; then
    [[ -x "${HOME:-/tmp}/.local/bin/cc-switch.AppImage" ]] || { warn "AppImage 未找到"; return 1; }
  else
    log "CC Switch 安装命令已完成，可从应用菜单启动"
  fi
}

install_component() {
  local component="$1" os="$2" arch="$3" distro="$4"
  case "$component" in
    claude) install_claude ;;
    codex) install_codex ;;
    hermes) install_hermes ;;
    cc-switch) install_cc_switch "$os" "$arch" "$distro" ;;
    *) warn "内部错误，未知组件: ${component}"; return 1 ;;
  esac
}

record_result() {
  RESULT_COMPONENTS+=("$1")
  RESULT_STATUSES+=("$2")
  RESULT_DURATIONS+=("$3")
  RESULT_DETAILS+=("$4")
}

run_component() {
  local component="$1" os="$2" arch="$3" distro="$4" label start status duration detail
  label="$(component_label "$component")"
  start="$(now_epoch)"
  CURRENT_PHASE="准备"
  log "---------- ${label} ----------"
  set +e
  install_component "$component" "$os" "$arch" "$distro"
  status=$?
  set -e
  duration=$(( $(now_epoch) - start ))
  if [[ $status -eq 0 ]]; then
    detail="完成"
    record_result "$label" "SUCCESS" "$duration" "$detail"
    ok "${label}: 成功（${duration}s）"
  else
    detail="阶段=${CURRENT_PHASE}, 退出码=${status}"
    record_result "$label" "FAILED" "$duration" "$detail"
    warn "${label}: 失败（${detail}），继续处理其他组件"
  fi
}

print_summary() {
  local i failed=0
  PROGRESS_CURRENT=$((PROGRESS_TOTAL - 1))
  progress_advance "生成安装汇总"
  finish_progress_line
  log "================ 安装汇总 ================"
  i=0
  while [[ $i -lt ${#RESULT_COMPONENTS[@]} ]]; do
    log "${RESULT_STATUSES[$i]} | ${RESULT_COMPONENTS[$i]} | ${RESULT_DURATIONS[$i]}s | ${RESULT_DETAILS[$i]}"
    [[ "${RESULT_STATUSES[$i]}" == "FAILED" ]] && failed=1
    i=$((i + 1))
  done
  if [[ ${#SKIPPED_COMPONENTS[@]} -gt 0 ]]; then log "SKIPPED | $(join_by_comma "${SKIPPED_COMPONENTS[@]}")"; fi
  log "日志文件: ${LOG_FILE}"
  log "总耗时: $(( $(now_epoch) - START_EPOCH ))s"
  [[ $failed -eq 0 ]]
}

main() {
  local os arch distro item summary_status
  resolve_selection
  init_log
  START_EPOCH="$(now_epoch)"
  make_temp_dir
  if [[ $QUIET -eq 0 && $NO_PROGRESS -eq 0 && -t 1 ]]; then TTY_PROGRESS=1; fi
  PROGRESS_TOTAL=$((2 + ${#SELECTED_COMPONENTS[@]} * 4 + 1))

  print_banner
  log "说明：只使用各项目官方安装源，不绕过地区、账号或服务条款限制。"
  log "日志文件: ${LOG_FILE}"

  os="$(detect_os)"
  arch="$(detect_arch)"
  distro="unknown"
  [[ "$os" == "linux" ]] && distro="$(detect_distro)"
  progress_advance "检测运行环境"
  log "系统信息: OS=${os} ARCH=${arch} DISTRO=${distro}"
  log "已选择: $(join_by_comma "${SELECTED_COMPONENTS[@]}")"
  [[ -n "$PROXY_URL" ]] && log "当前进程代理: $(redact_url "$PROXY_URL")"
  [[ -n "$GITHUB_PROXY" ]] && warn "已启用用户指定的 GitHub 代理前缀: $(redact_url "$GITHUB_PROXY")"
  if [[ $DEBUG_MODE -eq 1 ]]; then
    debug "Bash=${BASH_VERSION:-unknown}"
    debug "PATH=${PATH}"
    debug "TMP_DIR=${TMP_DIR}"
  fi

  progress_advance "检查网络与官方源"
  network_check

  for item in "${SELECTED_COMPONENTS[@]}"; do
    run_component "$item" "$os" "$arch" "$distro"
  done

  set +e
  print_summary
  summary_status=$?
  set -e
  if [[ $DRY_RUN -eq 1 ]]; then log "Dry-run 完成，未修改系统"; fi
  return "$summary_status"
}

main "$@"
