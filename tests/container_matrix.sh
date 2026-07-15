#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_case() {
  local os="$1" distro="$2" arch="$3"
  local log
  log="$(mktemp)"
  INSTALLER_TEST_OS="$os" INSTALLER_TEST_DISTRO="$distro" INSTALLER_TEST_ARCH="$arch" \
    bash "$ROOT/install.sh" --install all --dry-run --non-interactive --skip-network-check --no-progress --log-file "$log" >/tmp/installer-smoke.out 2>&1
  grep -q '安装汇总' /tmp/installer-smoke.out
  grep -q 'selected=claude,codex,hermes,cc-switch' "$log"
  rm -f "$log"
}
run_case linux kali x86_64
run_case linux debian arm64
run_case linux fedora x86_64
run_case linux arch x86_64
run_case macos unknown arm64
printf 'container matrix: PASS\n'
