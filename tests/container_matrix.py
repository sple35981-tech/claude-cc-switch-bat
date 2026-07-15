from __future__ import annotations

import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def write_exe(path: pathlib.Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


def fake_environment(base: pathlib.Path) -> dict[str, str]:
    fake_bin = base / "bin"
    fake_bin.mkdir()
    installed = base / "installed"
    installed.mkdir()
    command_log = base / "commands.log"
    api = {
        "assets": [
            {"name": "CC-Switch-v9.9.9-Linux-x86_64.deb", "browser_download_url": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.deb"},
            {"name": "CC-Switch-v9.9.9-Linux-x86_64.rpm", "browser_download_url": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.rpm"},
            {"name": "CC-Switch-v9.9.9-Linux-x86_64.AppImage", "browser_download_url": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.AppImage"},
            {"name": "CC-Switch-v9.9.9-macOS.zip", "browser_download_url": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-macOS.zip"},
        ]
    }
    api_json = json.dumps(api)
    write_exe(
        fake_bin / "curl",
        f'''#!/usr/bin/env bash
set -e
out=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[[ -n "$out" ]] || exit 0
if [[ -n "${{FAKE_CURL_FAIL_PATTERN:-}}" && "$url" == *"$FAKE_CURL_FAIL_PATTERN"* ]]; then
  exit 22
fi
case "$url" in
  *api.github.com*) cat > "$out" <<'EOF'
{api_json}
EOF
    ;;
  *claude.ai/install.sh*) cat > "$out" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$FAKE_INSTALL_BIN"
printf '#!/usr/bin/env bash\necho claude-test\n' > "$FAKE_INSTALL_BIN/claude"
chmod +x "$FAKE_INSTALL_BIN/claude"
EOF
    ;;
  *chatgpt.com/codex/install.sh*) cat > "$out" <<'EOF'
#!/usr/bin/env sh
mkdir -p "$FAKE_INSTALL_BIN"
printf '#!/usr/bin/env sh\necho codex-test\n' > "$FAKE_INSTALL_BIN/codex"
chmod +x "$FAKE_INSTALL_BIN/codex"
EOF
    ;;
  *hermes-agent.nousresearch.com/install.sh*) cat > "$out" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$FAKE_INSTALL_BIN"
printf '#!/usr/bin/env bash\necho hermes-test\n' > "$FAKE_INSTALL_BIN/hermes"
chmod +x "$FAKE_INSTALL_BIN/hermes"
EOF
    ;;
  *) printf 'package' > "$out" ;;
esac
''',
    )
    write_exe(
        fake_bin / "sudo",
        '#!/usr/bin/env bash\nexec "$@"\n',
    )
    for cmd in ("apt", "dpkg", "dnf", "yum", "zypper", "rpm"):
        write_exe(
            fake_bin / cmd,
            f'#!/usr/bin/env bash\necho "{cmd} $*" >> "$FAKE_COMMAND_LOG"\n'
            f'if [[ "${{FAKE_PACKAGE_FAIL:-}}" == "{cmd}" ]]; then exit 100; fi\nexit 0\n',
        )
    write_exe(
        fake_bin / "unzip",
        '#!/usr/bin/env bash\nout=""\nwhile [[ $# -gt 0 ]]; do case "$1" in -d) out="$2"; shift 2;; *) shift;; esac; done\nmkdir -p "$out/CC Switch.app"\n',
    )
    write_exe(fake_bin / "ditto", '#!/usr/bin/env bash\nmkdir -p "$2"\n')
    env = os.environ.copy()
    env.update(
        {
            "PATH": str(installed) + os.pathsep + str(fake_bin) + os.pathsep + env["PATH"],
            "HOME": str(base / "home"),
            "FAKE_INSTALL_BIN": str(installed),
            "FAKE_COMMAND_LOG": str(command_log),
            "INSTALLER_TEST_APPLICATIONS_DIR": str(base / "Applications"),
            "NO_COLOR": "1",
        }
    )
    return env


def run_case(
    name: str,
    os_name: str,
    arch: str,
    distro: str,
    selection: str = "all",
    fail: str = "",
    extra_env: dict[str, str] | None = None,
    expected_text: str = "",
) -> None:
    with tempfile.TemporaryDirectory(prefix=f"installer-{name}-") as td:
        base = pathlib.Path(td)
        env = fake_environment(base)
        env.update(
            {
                "INSTALLER_TEST_OS": os_name,
                "INSTALLER_TEST_ARCH": arch,
                "INSTALLER_TEST_DISTRO": distro,
            }
        )
        if fail:
            env["INSTALLER_TEST_FAIL_COMPONENT"] = fail
        if extra_env:
            env.update(extra_env)
        log_path = base / "run.log"
        result = subprocess.run(
            [
                "bash", str(ROOT / "install.sh"), "--install", selection,
                "--non-interactive", "--skip-network-check", "--no-progress",
                "--log-file", str(log_path),
            ],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
        expected = 1 if (fail or extra_env) else 0
        if result.returncode != expected:
            raise AssertionError(f"{name}: expected {expected}, got {result.returncode}\n{output}")
        if not log_path.exists():
            raise AssertionError(f"{name}: log not created\n{output}")
        if expected and "失败阶段" not in output:
            raise AssertionError(f"{name}: failure stage missing\n{output}")
        if expected_text and expected_text not in output:
            raise AssertionError(f"{name}: expected text {expected_text!r} missing\n{output}")
        mode = log_path.stat().st_mode & 0o777
        if mode & 0o077:
            raise AssertionError(f"{name}: log permissions are {oct(mode)}, expected user-only")
        if not expected and "安装汇总" not in output:
            raise AssertionError(f"{name}: summary missing\n{output}")
        print(f"PASS {name}")


def main() -> None:
    run_case("kali-deb", "linux", "x86_64", "kali")
    run_case("debian-deb", "linux", "x86_64", "debian", "cc-switch")
    run_case("fedora-rpm", "linux", "x86_64", "fedora", "cc-switch")
    run_case("arch-appimage", "linux", "x86_64", "arch", "cc-switch")
    run_case("macos-arm64", "macos", "arm64", "unknown", "cc-switch")
    run_case("failure-continues", "linux", "x86_64", "kali", "claude,codex", "claude")
    run_case(
        "download-failure",
        "linux",
        "x86_64",
        "kali",
        "codex,hermes",
        extra_env={"FAKE_CURL_FAIL_PATTERN": "codex/install.sh"},
        expected_text="下载安装器失败",
    )
    run_case(
        "apt-failure",
        "linux",
        "x86_64",
        "kali",
        "cc-switch",
        extra_env={"FAKE_PACKAGE_FAIL": "apt"},
        expected_text="APT 安装失败",
    )


if __name__ == "__main__":
    main()
