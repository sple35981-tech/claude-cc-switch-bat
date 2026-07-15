#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAKE_BIN="$WORK/bin"
CALLS="$WORK/calls.log"
URLS="$WORK/urls.log"
mkdir -p "$FAKE_BIN"
: >"$CALLS"
: >"$URLS"

cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
out=""
url=""
head_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) out="$2"; shift 2 ;;
    --head|-I) head_only=1; shift ;;
    --continue-at|-C|--retry|--retry-delay|--connect-timeout|--max-time|--user-agent) shift 2 ;;
    --fail|--location|--retry-all-errors|--progress-bar|--silent|--show-error) shift ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >>"${INSTALLER_TEST_URLS}"
[[ "$url" == https://* ]] || { printf 'bad URL: %s\n' "$url" >&2; exit 3; }
[[ $head_only -eq 1 ]] && exit 0
[[ -n "$out" ]] || exit 0
mkdir -p "$(dirname "$out")"
case "$url" in
  *api.github.com/repos/farion1231/cc-switch/releases/latest)
    cat >"$out" <<'JSON'
{"assets":[
{"name":"CC-Switch-v9.9.9-Linux-x86_64.deb","browser_download_url":"https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.deb"},
{"name":"CC-Switch-v9.9.9-Linux-x86_64.rpm","browser_download_url":"https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.rpm"},
{"name":"CC-Switch-v9.9.9-Linux-x86_64.AppImage","browser_download_url":"https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.AppImage"},
{"name":"CC-Switch-v9.9.9-macOS.zip","browser_download_url":"https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-macOS.zip"}
]}
JSON
    ;;
  *install.sh)
    printf '#!/bin/sh\nexit 0\n' >"$out"
    chmod +x "$out"
    ;;
  *) printf 'fake-package-content\n' >"$out" ;;
esac
EOF
chmod +x "$FAKE_BIN/curl"

for command in apt dpkg dnf zypper yum rpm brew unzip ditto sudo; do
  cat >"$FAKE_BIN/$command" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' '$command' "\$*" >>"${CALLS}"
exit 0
EOF
  chmod +x "$FAKE_BIN/$command"
done

# macOS path uses brew, so zip extraction is not needed in the simulated case.

run_case() {
  local name="$1" os="$2" distro="$3" selection="$4"
  local home="$WORK/home-$name" log="$WORK/$name.log" output="$WORK/$name.out"
  mkdir -p "$home"
  printf '[matrix] %s\n' "$name"
  env \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    HOME="$home" \
    INSTALLER_TEST_URLS="$URLS" \
    INSTALLER_TEST_OS="$os" \
    INSTALLER_TEST_ARCH="x86_64" \
    INSTALLER_TEST_DISTRO="$distro" \
    bash "$ROOT/install.sh" \
      --install "$selection" \
      --non-interactive \
      --skip-network-check \
      --no-progress \
      --log-file "$log" >"$output" 2>&1
  grep -q '100%' "$output"
  grep -q '安装汇总' "$output"
  grep -q 'SUCCESS' "$output"
  [[ -s "$log" ]]
}

run_case kali linux kali all
run_case debian linux debian cc-switch
run_case fedora linux fedora cc-switch
run_case arch linux arch cc-switch
run_case macos macos unknown cc-switch

# no-tty must remain line oriented and contain no carriage-return animation.
NO_TTY_OUT="$WORK/no-tty.out"
env PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$WORK/no-tty-home" INSTALLER_TEST_URLS="$URLS" \
  INSTALLER_TEST_OS=linux INSTALLER_TEST_ARCH=x86_64 INSTALLER_TEST_DISTRO=kali \
  bash "$ROOT/install.sh" --install codex --dry-run --non-interactive --skip-network-check \
    --log-file "$WORK/no-tty.log" < /dev/null >"$NO_TTY_OUT" 2>&1
grep -q '\[STEP ' "$NO_TTY_OUT"
if grep -q $'\r' "$NO_TTY_OUT"; then echo 'no-tty output contains CR' >&2; exit 1; fi

# failure: Claude fails, Codex still runs, final status is nonzero.
FAIL_OUT="$WORK/failure.out"
set +e
env PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$WORK/failure-home" INSTALLER_TEST_URLS="$URLS" \
  INSTALLER_TEST_OS=linux INSTALLER_TEST_ARCH=x86_64 INSTALLER_TEST_DISTRO=kali \
  INSTALLER_TEST_FAIL_COMPONENT=claude \
  bash "$ROOT/install.sh" --install claude,codex --dry-run --non-interactive --skip-network-check \
    --no-progress --log-file "$WORK/failure.log" >"$FAIL_OUT" 2>&1
status=$?
set -e
[[ $status -ne 0 ]]
grep -q 'Claude Code: 失败' "$FAIL_OUT"
grep -q 'Codex CLI: 成功' "$FAIL_OUT"

# Every captured network argument must be one clean HTTPS URL. This is the URL-pollution regression.
while IFS= read -r url; do
  [[ -z "$url" ]] && continue
  [[ "$url" == https://* ]] || { echo "polluted URL: $url" >&2; exit 1; }
  [[ "$url" != *'[INFO]'* ]] || { echo "log polluted URL: $url" >&2; exit 1; }
done <"$URLS"

# Confirm the expected package paths were exercised without invoking real package managers.
grep -q '^apt ' "$CALLS"
grep -q '^dnf ' "$CALLS"
grep -q '^brew ' "$CALLS"
[[ -x "$WORK/home-arch/.local/bin/cc-switch.AppImage" ]]

echo '[matrix] all simulated container cases passed'
