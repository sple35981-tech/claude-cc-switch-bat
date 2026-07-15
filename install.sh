#!/usr/bin/env bash
set -Eeuo pipefail

PROGRAM_NAME="AI CLI Installer Collector"
PROGRAM_VERSION="2.1.0"
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
QUIET=0
NO_PROGRESS=0
DEBUG_INSTALLER=0
DRY_RUN=0
NON_INTERACTIVE=0
SKIP_NETWORK_CHECK=0
SKIP_CLAUDE=0
SKIP_CODEX=0
SKIP_HERMES=0
SKIP_CC_SWITCH=0
TMP_DIR=""
OS_NAME=""
ARCH_NAME=""
DISTRO_NAME="unknown"
CURRENT_STEP=0
TOTAL_STEPS=1
DYNAMIC_PROGRESS=0
PROGRESS_LINE_ACTIVE=0
RUN_STARTED_AT="$(date +%s 2>/dev/null || printf '0')"

SELECTED_COMPONENTS=()
SUCCEEDED_COMPONENTS=()
FAILED_COMPONENTS=()
SKIPPED_COMPONENTS=()
FAILURE_DETAILS=()

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
  --dry-run                 只展示操作，不下载或安装
  --non-interactive         禁用菜单；未选择时默认 Claude Code + CC Switch
  --skip-network-check      跳过安装前网络诊断
  --quiet                   只显示错误和最终汇总
  --no-progress             禁用动态进度条，使用逐行进度输出
  --log-file PATH           指定日志文件（别名：--log）
  --debug                   记录更详细的诊断信息，不输出敏感环境变量
  -h, --help                显示帮助

示例:
  ./install.sh
  ./install.sh --install all
  ./install.sh --install codex,hermes --no-progress
  ./install.sh --install cc-switch --log-file ~/cc-switch-install.log
  ./install.sh --proxy http://127.0.0.1:7890
  ./install.sh --dry-run --install all --skip-network-check
EOF
}

raw_error() { printf '[ERROR] %s\n' "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) [[ $# -ge 2 ]] || { raw_error "--install 缺少组件列表"; exit 2; }; RAW_SELECTION="$2"; shift 2 ;;
    --channel) [[ $# -ge 2 ]] || { raw_error "--channel 缺少 stable 或 latest"; exit 2; }; CHANNEL="$2"; shift 2 ;;
    --proxy) [[ $# -ge 2 ]] || { raw_error "--proxy 缺少 URL"; exit 2; }; PROXY_URL="$2"; shift 2 ;;
    --github-proxy) [[ $# -ge 2 ]] || { raw_error "--github-proxy 缺少 URL"; exit 2; }; GITHUB_PROXY="$2"; shift 2 ;;
    --skip-claude) SKIP_CLAUDE=1; shift ;;
    --skip-codex) SKIP_CODEX=1; shift ;;
    --skip-hermes) SKIP_HERMES=1; shift ;;
    --skip-cc-switch) SKIP_CC_SWITCH=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --skip-network-check) SKIP_NETWORK_CHECK=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --no-progress) NO_PROGRESS=1; shift ;;
    --log-file|--log) [[ $# -ge 2 ]] || { raw_error "${1} 缺少路径"; exit 2; }; LOG_FILE="$2"; shift 2 ;;
    --debug) DEBUG_INSTALLER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) raw_error "未知参数: ${1}（使用 --help 查看帮助）"; exit 2 ;;
  esac
done

[[ "${CHANNEL}" == "stable" || "${CHANNEL}" == "latest" ]] || { raw_error "--channel 只支持 stable 或 latest"; exit 2; }

safe_timestamp() { date '+%Y%m%d-%H%M%S' 2>/dev/null || printf 'installer'; }

init_log() {
  if [[ -z "${LOG_FILE}" ]]; then
    LOG_FILE="${HOME:-/tmp}/.ai-cli-installer/logs/$(safe_timestamp).log"
  fi
  mkdir -p "$(dirname "${LOG_FILE}")" || { raw_error "无法创建日志目录: $(dirname "${LOG_FILE}")"; exit 1; }
  : > "${LOG_FILE}" || { raw_error "无法写入日志文件: ${LOG_FILE}"; exit 1; }
  chmod 600 "${LOG_FILE}" 2>/dev/null || true
  write_log INFO "${PROGRAM_NAME} v${PROGRAM_VERSION}"
}

write_log() {
  local level="$1"; shift
  local stamp
  stamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf 'time')"
  printf '%s [%s] %s\n' "${stamp}" "${level}" "$*" >> "${LOG_FILE}"
}

finish_progress_line() {
  if [[ ${PROGRESS_LINE_ACTIVE} -eq 1 ]]; then
    printf '\n' >&2
    PROGRESS_LINE_ACTIVE=0
  fi
}

emit_terminal() {
  local level="$1"; shift
  finish_progress_line
  printf '[%s] %s\n' "${level}" "$*" >&2
}

info() {
  write_log INFO "$*"
  [[ ${QUIET} -eq 1 ]] || emit_terminal INFO "$*"
}

warn() {
  write_log WARN "$*"
  emit_terminal WARN "$*"
}

error() {
  write_log ERROR "$*"
  emit_terminal ERROR "$*"
}

debug_log() {
  [[ ${DEBUG_INSTALLER} -eq 1 ]] || return 0
  write_log DEBUG "$*"
  [[ ${QUIET} -eq 1 ]] || emit_terminal DEBUG "$*"
}

summary_line() {
  write_log SUMMARY "$*"
  emit_terminal INFO "$*"
}

supports_dynamic_progress() {
  [[ ${NO_PROGRESS} -eq 0 && ${QUIET} -eq 0 ]] || return 1
  [[ -z "${CI:-}" ]] || return 1
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ -t 2 ]] || return 1
  return 0
}

render_bar() {
  local percent="$1" width=24 filled empty bar="" i
  filled=$((percent * width / 100))
  empty=$((width - filled))
  i=0
  while [[ ${i} -lt ${filled} ]]; do bar="${bar}#"; i=$((i + 1)); done
  i=0
  while [[ ${i} -lt ${empty} ]]; do bar="${bar}-"; i=$((i + 1)); done
  printf '%s' "${bar}"
}

progress_step() {
  local message="$1" percent bar
  CURRENT_STEP=$((CURRENT_STEP + 1))
  [[ ${CURRENT_STEP} -le ${TOTAL_STEPS} ]] || CURRENT_STEP=${TOTAL_STEPS}
  percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
  write_log PROGRESS "${percent}% ${message}"
  [[ ${QUIET} -eq 1 ]] && return 0
  if [[ ${DYNAMIC_PROGRESS} -eq 1 ]]; then
    bar="$(render_bar "${percent}")"
    printf '\r[PROGRESS] [%s] %3d%% %s' "${bar}" "${percent}" "${message}" >&2
    PROGRESS_LINE_ACTIVE=1
  else
    emit_terminal PROGRESS "${percent}% ${message}"
  fi
}

component_count() { printf '%s' "${#SELECTED_COMPONENTS[@]}"; }

contains_component() {
  local wanted="$1" item
  [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]] || return 1
  for item in "${SELECTED_COMPONENTS[@]}"; do
    [[ "${item}" == "${wanted}" ]] && return 0
  done
  return 1
}

append_unique_component() {
  local component="$1"
  contains_component "${component}" || SELECTED_COMPONENTS+=("${component}")
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
  token="$(printf '%s' "${token}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "${token}" in
    1|claude|claude-code|claudecode) printf 'claude' ;;
    2|codex|codex-cli|codexcli) printf 'codex' ;;
    3|hermes|hermes-agent|hermesagent) printf 'hermes' ;;
    4|cc-switch|ccswitch|cc_switch) printf 'cc-switch' ;;
    5|all|'*') printf 'all' ;;
    0|exit|quit|q) printf 'exit' ;;
    '') printf '' ;;
    *) return 2 ;;
  esac
}

parse_selection() {
  local raw="$1" token normalized old_ifs
  local tokens=()
  raw="${raw// /,}"
  old_ifs="${IFS}"
  IFS=','
  # shellcheck disable=SC2206
  tokens=( ${raw} )
  IFS="${old_ifs}"
  [[ ${#tokens[@]} -gt 0 ]] || return 1
  for token in "${tokens[@]}"; do
    if ! normalized="$(normalize_selection_token "${token}")"; then
      error "未知组件: ${token}。可选 claude、codex、hermes、cc-switch、all"
      return 2
    fi
    case "${normalized}" in
      '') ;;
      exit) exit 0 ;;
      all)
        append_unique_component claude
        append_unique_component codex
        append_unique_component hermes
        append_unique_component cc-switch
        ;;
      *) append_unique_component "${normalized}" ;;
    esac
  done
}

has_interactive_tty() { [[ -r /dev/tty && -w /dev/tty ]] && { [[ -t 0 ]] || [[ -t 1 ]] || [[ -t 2 ]]; }; }

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
  IFS= read -r selection </dev/tty || return 1
  printf '%s' "${selection}"
}

remove_skipped_components() {
  local item
  local filtered=()
  [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]] || return 0
  for item in "${SELECTED_COMPONENTS[@]}"; do
    case "${item}" in
      claude) [[ ${SKIP_CLAUDE} -eq 1 ]] && { SKIPPED_COMPONENTS+=("Claude Code"); continue; } ;;
      codex) [[ ${SKIP_CODEX} -eq 1 ]] && { SKIPPED_COMPONENTS+=("Codex CLI"); continue; } ;;
      hermes) [[ ${SKIP_HERMES} -eq 1 ]] && { SKIPPED_COMPONENTS+=("Hermes Agent"); continue; } ;;
      cc-switch) [[ ${SKIP_CC_SWITCH} -eq 1 ]] && { SKIPPED_COMPONENTS+=("CC Switch"); continue; } ;;
    esac
    filtered+=("${item}")
  done
  SELECTED_COMPONENTS=()
  [[ ${#filtered[@]} -gt 0 ]] && SELECTED_COMPONENTS=("${filtered[@]}")
}

resolve_selection() {
  local selection="${RAW_SELECTION}"
  if [[ -z "${selection}" && -n "${INSTALLER_TEST_SELECTION:-}" ]]; then
    selection="${INSTALLER_TEST_SELECTION}"
  elif [[ -z "${selection}" && ${NON_INTERACTIVE} -eq 0 ]] && has_interactive_tty; then
    selection="$(show_menu_and_read_selection)" || { error "无法读取选择"; return 1; }
  elif [[ -z "${selection}" ]]; then
    selection="claude,cc-switch"
    info "未检测到交互终端，使用兼容默认选择: Claude Code + CC Switch"
  fi
  parse_selection "${selection}" || return
  remove_skipped_components
  [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]] || { error "没有可安装组件，请使用 --install 选择至少一项"; return 1; }
}

join_by_comma() {
  local first=1 item
  for item in "$@"; do
    [[ ${first} -eq 1 ]] || printf ', '
    printf '%s' "${item}"
    first=0
  done
}

selected_csv() {
  [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]] || return 0
  local old_ifs="${IFS}"
  IFS=','
  printf '%s' "${SELECTED_COMPONENTS[*]}"
  IFS="${old_ifs}"
}

quote_cmd() {
  local out="" arg quoted
  for arg in "$@"; do
    printf -v quoted '%q' "${arg}"
    out="${out}${quoted} "
  done
  printf '%s' "${out% }"
}

run_logged() {
  local description="$1"; shift
  info "${description}"
  write_log COMMAND "$(quote_cmd "$@")"
  [[ ${DRY_RUN} -eq 0 ]] || { info "Dry-run 命令: $(quote_cmd "$@")"; return 0; }
  if [[ ${QUIET} -eq 1 ]]; then
    "$@" >>"${LOG_FILE}" 2>&1
  else
    set +e
    "$@" 2>&1 | tee -a "${LOG_FILE}"
    local status=${PIPESTATUS[0]}
    set -e
    return ${status}
  fi
}

as_root() {
  local description="$1"; shift
  if [[ $(id -u) -eq 0 ]]; then
    run_logged "${description}" "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run_logged "${description}" sudo "$@"
  else
    error "安装系统软件需要 root 权限，但未找到 sudo"
    return 1
  fi
}

redact_url() {
  printf '%s' "$1" | sed -E 's#(https?://)[^/@]+@#\1***@#'
}

apply_github_proxy() {
  local url="$1"
  if [[ -z "${GITHUB_PROXY}" ]]; then
    printf '%s' "${url}"
  else
    printf '%s%s' "${GITHUB_PROXY%/}/" "${url}"
  fi
}

file_size() {
  local file="$1"
  if command -v stat >/dev/null 2>&1; then
    stat -c '%s' "${file}" 2>/dev/null || stat -f '%z' "${file}" 2>/dev/null || wc -c <"${file}"
  else
    wc -c <"${file}"
  fi
}

sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  else
    printf 'unavailable'
  fi
}

record_file_metadata() {
  local file="$1" label="$2" size hash
  [[ ${DRY_RUN} -eq 0 ]] || { info "${label}: Dry-run，跳过本地 SHA-256 计算"; return 0; }
  [[ -f "${file}" ]] || { error "下载文件不存在: ${file}"; return 1; }
  size="$(file_size "${file}")"
  hash="$(sha256_of "${file}")"
  info "${label}: 大小 ${size} bytes；本地 SHA-256 ${hash}"
  write_log ARTIFACT "label=${label} path=${file} size=${size} sha256=${hash}"
}

download() {
  local url="$1" dest="$2" label="${3:-文件}"
  local safe_url
  safe_url="$(redact_url "${url}")"
  info "下载 ${label}: ${safe_url}"
  write_log DOWNLOAD "url=${safe_url} destination=${dest}"
  [[ ${DRY_RUN} -eq 0 ]] || return 0
  mkdir -p "$(dirname "${dest}")" || return 1
  if command -v curl >/dev/null 2>&1; then
    local curl_args=()
    curl_args=(--fail --location --show-error --retry 4 --retry-delay 2 --connect-timeout 15 --max-time 1800 --continue-at - --user-agent "ai-cli-installer/${PROGRAM_VERSION}" --output "${dest}")
    if curl --help all 2>/dev/null | grep -q -- '--retry-all-errors'; then
      curl_args+=(--retry-all-errors)
    fi
    if [[ ${DYNAMIC_PROGRESS} -eq 1 && ${QUIET} -eq 0 ]]; then
      curl_args+=(--progress-bar)
    else
      curl_args+=(--silent)
    fi
    set +e
    curl "${curl_args[@]}" "${url}" 2> >(tee -a "${LOG_FILE}" >&2)
    local status=$?
    set -e
    if [[ ${status} -ne 0 && -s "${dest}" ]]; then
      warn "断点续传失败，删除部分文件后重试一次"
      rm -f "${dest}"
      set +e
      curl "${curl_args[@]}" "${url}" 2> >(tee -a "${LOG_FILE}" >&2)
      status=$?
      set -e
    fi
    return ${status}
  elif command -v wget >/dev/null 2>&1; then
    local wget_args=(--tries=4 --timeout=30 --continue --user-agent="ai-cli-installer/${PROGRAM_VERSION}" -O "${dest}" "${url}")
    if [[ ${QUIET} -eq 1 ]]; then
      wget_args=(--quiet "${wget_args[@]}")
    fi
    run_logged "使用 wget 下载 ${label}" wget "${wget_args[@]}"
  else
    error "需要 curl 或 wget 才能下载文件"
    return 1
  fi
}

network_check_url() {
  local label="$1" url="$2"
  if command -v curl >/dev/null 2>&1; then
    if curl --head --location --silent --show-error --connect-timeout 8 --max-time 20 "${url}" >/dev/null 2>>"${LOG_FILE}"; then
      info "网络检查通过: ${label}"
    else
      warn "无法访问 ${label}: ${url}；安装阶段仍会按重试策略继续"
    fi
  else
    warn "未找到 curl，跳过 ${label} 网络预检"
  fi
}

network_check() {
  [[ ${SKIP_NETWORK_CHECK} -eq 0 && ${DRY_RUN} -eq 0 ]] || { info "已跳过网络预检"; return 0; }
  contains_component claude && network_check_url "Claude" "https://claude.ai"
  contains_component codex && network_check_url "Codex" "https://chatgpt.com"
  contains_component hermes && network_check_url "Hermes" "https://hermes-agent.nousresearch.com"
  contains_component cc-switch && network_check_url "GitHub API" "https://api.github.com"
  return 0
}

detect_os() {
  if [[ -n "${INSTALLER_TEST_OS:-}" ]]; then printf '%s' "${INSTALLER_TEST_OS}"; return; fi
  case "$(uname -s)" in
    Darwin) printf 'macos' ;;
    Linux) printf 'linux' ;;
    *) return 1 ;;
  esac
}

detect_arch() {
  local machine="${INSTALLER_TEST_ARCH:-$(uname -m)}"
  case "${machine}" in
    x86_64|amd64|AMD64) printf 'x86_64' ;;
    arm64|aarch64|ARM64) printf 'arm64' ;;
    *) return 1 ;;
  esac
}

detect_distro() {
  if [[ -n "${INSTALLER_TEST_DISTRO:-}" ]]; then printf '%s' "${INSTALLER_TEST_DISTRO}"; return; fi
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s' "${ID:-unknown}"
  else
    printf 'unknown'
  fi
}

make_temp_dir() {
  if [[ ${DRY_RUN} -eq 1 ]]; then
    TMP_DIR="${TMPDIR:-/tmp}/ai-cli-installer-dry-run"
    mkdir -p "${TMP_DIR}"
  else
    TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t ai-cli-installer)"
  fi
}

cleanup() {
  finish_progress_line
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" && ${DEBUG_INSTALLER} -eq 0 ]]; then
    rm -rf "${TMP_DIR}"
  elif [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    write_log DEBUG "保留临时目录: ${TMP_DIR}"
  fi
}
on_signal() {
  local signal_name="$1"
  error "收到信号 ${signal_name}，安装已中止"
  exit 130
}
trap cleanup EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

stage() {
  local component="$1" message="$2"
  progress_step "${component}: ${message}"
}

verify_command() {
  local command_name="$1" label="$2"
  [[ ${DRY_RUN} -eq 0 ]] || { info "${label}: Dry-run 验证通过"; return 0; }
  if command -v "${command_name}" >/dev/null 2>&1; then
    local version
    version="$("${command_name}" --version 2>&1 | head -n 1 || true)"
    info "${label}: 已检测到 ${version:-${command_name}}"
  else
    warn "${label}: 当前 Shell 尚未找到 ${command_name}，通常重新打开终端后生效"
  fi
  return 0
}

install_script_component() {
  local component="$1" label="$2" source_label="$3" url="$4" shell_name="$5" installer="$6"
  stage "${label}" "准备官方安装源"
  info "${label} 来源: ${source_label} (${url})"
  [[ "${INSTALLER_TEST_FAIL_COMPONENT:-}" == "${component}" ]] && { error "${label}: 测试注入失败"; return 97; }

  stage "${label}" "下载官方安装器"
  download "${url}" "${installer}" "${label} 安装器" || return

  stage "${label}" "记录安装器信息"
  record_file_metadata "${installer}" "${label} 安装器" || return

  stage "${label}" "执行安装"
  if [[ ${DRY_RUN} -eq 1 ]]; then
    info "Dry-run 命令: ${shell_name} ${installer}${component:+}"
  else
    chmod 700 "${installer}" || return
    if [[ "${component}" == "claude" ]]; then
      run_logged "执行 ${label} 官方安装器（通道: ${CHANNEL}）" "${shell_name}" "${installer}" "${CHANNEL}" || return
    else
      run_logged "执行 ${label} 官方安装器" "${shell_name}" "${installer}" || return
    fi
  fi

  stage "${label}" "验证安装结果"
  verify_command "${component}" "${label}"
}

install_claude() { install_script_component claude "Claude Code" "Anthropic 官方安装器" "${CLAUDE_INSTALL_URL}" bash "${TMP_DIR}/claude-install.sh"; }
install_codex() { install_script_component codex "Codex CLI" "OpenAI 官方安装器" "${CODEX_INSTALL_URL}" sh "${TMP_DIR}/codex-install.sh"; }
install_hermes() { install_script_component hermes "Hermes Agent" "Nous Research 官方安装器" "${HERMES_INSTALL_URL}" bash "${TMP_DIR}/hermes-install.sh"; }

release_asset_url() {
  local pattern="$1" json="${TMP_DIR}/cc-switch-release.json" url=""
  if [[ -n "${INSTALLER_FAKE_ASSET_URL:-}" ]]; then printf '%s' "${INSTALLER_FAKE_ASSET_URL}"; return 0; fi
  if [[ ${DRY_RUN} -eq 1 ]]; then
    case "${pattern}" in
      *macOS*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-macOS.zip' "${CC_SWITCH_REPO}" ;;
      *Linux-x86_64*deb*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-x86_64.deb' "${CC_SWITCH_REPO}" ;;
      *Linux-arm64*deb*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-arm64.deb' "${CC_SWITCH_REPO}" ;;
      *Linux-x86_64*rpm*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-x86_64.rpm' "${CC_SWITCH_REPO}" ;;
      *Linux-arm64*rpm*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-arm64.rpm' "${CC_SWITCH_REPO}" ;;
      *Linux-arm64*AppImage*) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-arm64.AppImage' "${CC_SWITCH_REPO}" ;;
      *) printf 'https://github.com/%s/releases/latest/download/CC-Switch-LATEST-Linux-x86_64.AppImage' "${CC_SWITCH_REPO}" ;;
    esac
    return 0
  fi

  # release metadata download logs are always on stderr; stdout is reserved for the returned URL.
  download "${GITHUB_API_URL}" "${json}" "CC Switch Release metadata" >&2 || return
  if command -v python3 >/dev/null 2>&1; then
    url="$(python3 - "${json}" "${pattern}" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    release = json.load(fh)
regex = re.compile(sys.argv[2], re.I)
for asset in release.get("assets", []):
    if regex.search(asset.get("name", "")):
        print(asset.get("browser_download_url", ""))
        break
PY
)"
  else
    url="$(grep -E '"browser_download_url"' "${json}" | sed -E 's/.*"(https:[^"]+)".*/\1/' | grep -Ei "${pattern}" | head -n 1 || true)"
  fi
  [[ -n "${url}" ]] || { error "未找到匹配的 CC Switch 安装包: ${pattern}"; return 1; }
  case "${url}" in
    https://github.com/*|https://objects.githubusercontent.com/*|https://github-releases.githubusercontent.com/*) ;;
    *) error "Release 返回了非 GitHub 下载地址，已拒绝: ${url}"; return 1 ;;
  esac
  printf '%s' "${url}"
}

cc_switch_extension() {
  local distro="$1"
  case "${distro}" in
    ubuntu|debian|linuxmint|pop|kali|zorin) printf 'deb' ;;
    fedora|rhel|centos|rocky|almalinux|ol|opensuse*|sles) printf 'rpm' ;;
    *) printf 'AppImage' ;;
  esac
}

verify_cc_switch() {
  local ext="$1" target="$2"
  [[ ${DRY_RUN} -eq 0 ]] || { info "CC Switch: Dry-run 验证通过"; return 0; }
  case "${ext}" in
    deb)
      if command -v dpkg-query >/dev/null 2>&1; then
        local package_info
        package_info="$(dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | grep -Ei 'cc[- ]?switch' | head -n 1 || true)"
        [[ -n "${package_info}" ]] && info "CC Switch: 已安装 ${package_info}" || warn "CC Switch: deb 已执行安装，但未从 dpkg-query 找到包名"
      fi
      ;;
    rpm)
      if command -v rpm >/dev/null 2>&1; then rpm -qa 2>/dev/null | grep -Ei 'cc[- ]?switch' | head -n 1 | while IFS= read -r line; do info "CC Switch: 已安装 ${line}"; done; fi
      ;;
    AppImage) [[ -x "${target}" ]] || { error "CC Switch AppImage 未正确安装: ${target}"; return 1; }; info "CC Switch AppImage: ${target}" ;;
    macOS) [[ -d /Applications/CC-Switch.app || -d /Applications/CC\ Switch.app ]] || warn "CC Switch: 请在 Launchpad 或 /Applications 中确认应用" ;;
  esac
  return 0
}

install_cc_switch() {
  local label="CC Switch" ext pattern url asset target=""
  stage "${label}" "获取官方 Release 信息"
  info "${label} 来源: ${CC_SWITCH_REPO} 官方 GitHub Releases"
  [[ "${INSTALLER_TEST_FAIL_COMPONENT:-}" == "cc-switch" ]] && { error "${label}: 测试注入失败"; return 97; }

  if [[ "${OS_NAME}" == "macos" ]] && command -v brew >/dev/null 2>&1; then
    stage "${label}" "由 Homebrew 获取安装包"
    info "Homebrew 将负责下载 CC Switch"
    stage "${label}" "记录包管理器校验信息"
    info "Homebrew 将执行其自身的包校验"
    stage "${label}" "执行 Homebrew 安装"
    run_logged "使用 Homebrew 安装 CC Switch" brew install --cask cc-switch || return
    stage "${label}" "验证应用"
    verify_cc_switch macOS ""
    return
  fi

  if [[ "${OS_NAME}" == "macos" ]]; then
    ext="macOS"
    pattern='CC-Switch-v.*-macOS\.zip$'
  else
    ext="$(cc_switch_extension "${DISTRO_NAME}")"
    pattern="CC-Switch-v.*-Linux-${ARCH_NAME}\.${ext}$"
  fi
  url="$(release_asset_url "${pattern}")" || return
  asset="${TMP_DIR}/$(basename "${url}")"

  stage "${label}" "下载安装包"
  download "$(apply_github_proxy "${url}")" "${asset}" "CC Switch ${ext}" || return

  stage "${label}" "记录安装包信息"
  record_file_metadata "${asset}" "CC Switch ${ext}" || return

  stage "${label}" "安装 ${ext} 包"
  case "${ext}" in
    deb)
      if command -v apt >/dev/null 2>&1; then as_root "使用 apt 安装 CC Switch" apt install -y "${asset}" || return
      else as_root "使用 dpkg 安装 CC Switch" dpkg -i "${asset}" || return; fi
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then as_root "使用 dnf 安装 CC Switch" dnf install -y "${asset}" || return
      elif command -v zypper >/dev/null 2>&1; then as_root "使用 zypper 安装 CC Switch" zypper --non-interactive install "${asset}" || return
      elif command -v yum >/dev/null 2>&1; then as_root "使用 yum 安装 CC Switch" yum install -y "${asset}" || return
      else as_root "使用 rpm 安装 CC Switch" rpm -Uvh "${asset}" || return; fi
      ;;
    AppImage)
      target="${HOME:-/tmp}/.local/bin/cc-switch.AppImage"
      run_logged "创建用户应用目录" mkdir -p "$(dirname "${target}")" "${HOME:-/tmp}/.local/share/applications" || return
      run_logged "复制 CC Switch AppImage" cp "${asset}" "${target}" || return
      run_logged "设置 AppImage 执行权限" chmod +x "${target}" || return
      if [[ ${DRY_RUN} -eq 0 ]]; then
        cat > "${HOME:-/tmp}/.local/share/applications/cc-switch.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CC Switch
Comment=Claude Code / Codex / Gemini CLI configuration manager
Exec=${target}
Terminal=false
Categories=Development;
EOF
      fi
      ;;
    macOS)
      if [[ ${DRY_RUN} -eq 0 ]]; then
        local extract="${TMP_DIR}/cc-switch-macos" app
        mkdir -p "${extract}" || return
        command -v unzip >/dev/null 2>&1 || { error "macOS ZIP 安装需要 unzip"; return 1; }
        run_logged "解压 CC Switch" unzip -q "${asset}" -d "${extract}" || return
        app="$(find "${extract}" -type d -name '*.app' -print | head -n 1)"
        [[ -n "${app}" ]] || { error "ZIP 中未找到 .app"; return 1; }
        if [[ -w /Applications ]]; then run_logged "复制 CC Switch 到 /Applications" ditto "${app}" "/Applications/$(basename "${app}")" || return
        else as_root "复制 CC Switch 到 /Applications" ditto "${app}" "/Applications/$(basename "${app}")" || return; fi
      else
        info "Dry-run: 将解压 ZIP 并复制到 /Applications"
      fi
      ;;
  esac

  stage "${label}" "验证安装结果"
  verify_cc_switch "${ext}" "${target}"
}

install_component() {
  case "$1" in
    claude) install_claude ;;
    codex) install_codex ;;
    hermes) install_hermes ;;
    cc-switch) install_cc_switch ;;
    *) error "内部错误，未知组件: ${1}"; return 1 ;;
  esac
}

run_component() {
  local component="$1" label before status completed
  label="$(component_label "${component}")"
  before=${CURRENT_STEP}
  info "========== ${label} =========="
  set +e
  install_component "${component}"
  status=$?
  set -e
  completed=$((CURRENT_STEP - before))
  while [[ ${completed} -lt 5 ]]; do
    progress_step "${label}: 因失败跳过后续阶段"
    completed=$((completed + 1))
  done
  if [[ ${status} -eq 0 ]]; then
    SUCCEEDED_COMPONENTS+=("${label}")
    info "${label}: 成功"
  else
    FAILED_COMPONENTS+=("${label}")
    FAILURE_DETAILS+=("${label}: exit ${status}")
    warn "${label}: 失败（退出码 ${status}），继续处理其他组件"
  fi
}

print_banner() {
  [[ ${QUIET} -eq 1 ]] && return 0
  emit_terminal INFO "${PROGRAM_NAME} v${PROGRAM_VERSION}"
  emit_terminal INFO "官方源安装；不绕过地区、账号或服务条款限制"
}

print_summary() {
  local elapsed now
  now="$(date +%s 2>/dev/null || printf '%s' "${RUN_STARTED_AT}")"
  elapsed=$((now - RUN_STARTED_AT))
  summary_line "========== 安装汇总 =========="
  [[ ${#SUCCEEDED_COMPONENTS[@]} -eq 0 ]] || summary_line "成功: $(join_by_comma "${SUCCEEDED_COMPONENTS[@]}")"
  [[ ${#SKIPPED_COMPONENTS[@]} -eq 0 ]] || summary_line "跳过: $(join_by_comma "${SKIPPED_COMPONENTS[@]}")"
  if [[ ${#FAILED_COMPONENTS[@]} -gt 0 ]]; then
    warn "失败: $(join_by_comma "${FAILED_COMPONENTS[@]}")"
    [[ ${#FAILURE_DETAILS[@]} -eq 0 ]] || write_log ERROR "details=$(join_by_comma "${FAILURE_DETAILS[@]}")"
  fi
  summary_line "耗时: ${elapsed}s"
  summary_line "日志: ${LOG_FILE}"
}

main() {
  init_log
  print_banner
  resolve_selection || { print_summary; return 2; }

  if [[ -n "${PROXY_URL}" ]]; then
    export HTTP_PROXY="${PROXY_URL}" HTTPS_PROXY="${PROXY_URL}" http_proxy="${PROXY_URL}" https_proxy="${PROXY_URL}"
  fi
  if [[ ${NON_INTERACTIVE} -eq 1 ]]; then
    export DEBIAN_FRONTEND=noninteractive
  fi
  supports_dynamic_progress && DYNAMIC_PROGRESS=1 || DYNAMIC_PROGRESS=0
  TOTAL_STEPS=$((2 + $(component_count) * 5 + 1))

  make_temp_dir
  progress_step "检测操作系统与架构"
  OS_NAME="$(detect_os)" || { error "不支持的系统: $(uname -s)"; return 2; }
  ARCH_NAME="$(detect_arch)" || { error "不支持的 CPU 架构: ${INSTALLER_TEST_ARCH:-$(uname -m)}"; return 2; }
  [[ "${OS_NAME}" == "linux" ]] && DISTRO_NAME="$(detect_distro)"
  info "检测到: OS=${OS_NAME} ARCH=${ARCH_NAME} DISTRO=${DISTRO_NAME}"

  local selection_text
  selection_text="$(selected_csv)"
  write_log CONTEXT "OS=${OS_NAME} ARCH=${ARCH_NAME} DISTRO=${DISTRO_NAME} selected=${selection_text} dry_run=${DRY_RUN} non_interactive=${NON_INTERACTIVE}"
  debug_log "temp_dir=${TMP_DIR} progress_dynamic=${DYNAMIC_PROGRESS} proxy_enabled=$([[ -n "${PROXY_URL}" ]] && printf yes || printf no)"
  [[ -z "${GITHUB_PROXY}" ]] || warn "已启用用户指定的 GitHub 下载前缀，请确认该服务可信"

  progress_step "检查所选官方服务的网络连通性"
  network_check

  local component
  for component in "${SELECTED_COMPONENTS[@]}"; do run_component "${component}"; done

  progress_step "生成安装汇总"
  finish_progress_line
  print_summary
  [[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]
}

main "$@"
