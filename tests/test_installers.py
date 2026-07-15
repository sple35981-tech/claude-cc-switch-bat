from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")


def decode(data: bytes) -> str:
    return data.decode("utf-8", errors="replace")


def run_bash(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[bytes]:
    merged = os.environ.copy()
    merged.update(
        {
            "LC_ALL": "C.UTF-8",
            "LANG": "C.UTF-8",
            "INSTALLER_TEST_OS": "linux",
            "INSTALLER_TEST_ARCH": "x86_64",
            "INSTALLER_TEST_DISTRO": "kali",
        }
    )
    if env:
        merged.update(env)
    return subprocess.run(
        [BASH or "bash", str(ROOT / "install.sh"), *args],
        cwd=ROOT,
        env=merged,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


class InstallerTests(unittest.TestCase):
    def test_bash_help_documents_progress_and_logging(self) -> None:
        result = run_bash("--help")
        output = decode(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, output)
        for option in ("--install", "--quiet", "--no-progress", "--log-file", "--debug"):
            self.assertIn(option, output)

    def test_bash_dry_run_all_has_staged_progress_and_summary(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_file = pathlib.Path(temp_dir) / "installer.log"
            result = run_bash(
                "--install",
                "all",
                "--dry-run",
                "--non-interactive",
                "--skip-network-check",
                "--no-progress",
                "--log-file",
                str(log_file),
            )
            output = decode(result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("[PROGRESS]", output)
            self.assertIn("准备", output)
            self.assertIn("下载", output)
            self.assertIn("安装汇总", output)
            self.assertIn("Claude Code", output)
            self.assertIn("Codex CLI", output)
            self.assertIn("Hermes Agent", output)
            self.assertIn("CC Switch", output)
            self.assertTrue(log_file.exists())
            log = log_file.read_text(encoding="utf-8")
            self.assertIn("AI CLI Installer Collector", log)
            self.assertIn("OS=linux", log)
            self.assertIn("selected=claude,codex,hermes,cc-switch", log)

    def test_bash_quiet_preserves_summary_and_errors(self) -> None:
        result = run_bash(
            "--install",
            "codex,hermes",
            "--dry-run",
            "--non-interactive",
            "--skip-network-check",
            "--quiet",
        )
        output = decode(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn("[PROGRESS]", output)
        self.assertIn("安装汇总", output)
        self.assertIn("成功", output)

    def test_bash_component_failure_continues_and_returns_nonzero(self) -> None:
        result = run_bash(
            "--install",
            "claude,codex",
            "--dry-run",
            "--non-interactive",
            "--skip-network-check",
            "--no-progress",
            env={"INSTALLER_TEST_FAIL_COMPONENT": "claude"},
        )
        output = decode(result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 0, output)
        self.assertIn("Claude Code", output)
        self.assertIn("失败", output)
        self.assertIn("Codex CLI", output)
        self.assertIn("成功", output)

    def test_release_metadata_log_cannot_pollute_asset_url(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertRegex(content, r"release_asset_url\(\)")
        self.assertIn("release metadata", content.lower())
        # All human-readable log helpers must write to stderr so command substitution remains pure.
        self.assertRegex(content, r"emit_terminal.*>&2|printf.*>&2")

    @unittest.skipUnless(BASH, "Bash required")
    def test_real_cc_switch_path_uses_clean_url_with_fake_network(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            calls = root / "calls.log"
            release = {
                "tag_name": "v9.9.9",
                "assets": [
                    {
                        "name": "CC-Switch-v9.9.9-Linux-x86_64.deb",
                        "browser_download_url": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.deb",
                    }
                ],
            }
            fake_curl = fake_bin / "curl"
            fake_curl.write_text(
                textwrap.dedent(
                    f"""\
                    #!/usr/bin/env bash
                    set -e
                    printf '%s\\n' "$*" >> {calls!s}
                    out=''
                    url=''
                    while [[ $# -gt 0 ]]; do
                      case "$1" in
                        -o|--output) out="$2"; shift 2 ;;
                        -*) shift ;;
                        *) url="$1"; shift ;;
                      esac
                    done
                    if [[ "$url" == *api.github.com* ]]; then
                      cat > "$out" <<'JSON'
                    {json.dumps(release)}
                    JSON
                    else
                      printf 'fake-deb' > "$out"
                    fi
                    """
                ),
                encoding="utf-8",
            )
            fake_curl.chmod(0o755)
            for name, body in {
                "apt": "#!/usr/bin/env bash\nprintf 'apt:%s\\n' \"$*\" >> \"$CALLS_LOG\"\nexit 0\n",
                "sudo": "#!/usr/bin/env bash\nexec \"$@\"\n",
                "dpkg-query": "#!/usr/bin/env bash\necho 'cc-switch 9.9.9'\nexit 0\n",
                "sha256sum": "#!/usr/bin/env bash\necho 'abc123  '$1\n",
            }.items():
                path = fake_bin / name
                path.write_text(body, encoding="utf-8")
                path.chmod(0o755)
            log_file = root / "run.log"
            env = {
                "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
                "CALLS_LOG": str(calls),
                "HOME": str(root / "home"),
            }
            result = run_bash(
                "--install",
                "cc-switch",
                "--non-interactive",
                "--skip-network-check",
                "--no-progress",
                "--log-file",
                str(log_file),
                env=env,
            )
            output = decode(result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, output)
            call_text = calls.read_text(encoding="utf-8")
            self.assertIn("https://api.github.com/repos/farion1231/cc-switch/releases/latest", call_text)
            self.assertIn("https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.deb", call_text)
            self.assertNotIn("[INFO]", call_text)
            self.assertNotIn("bad range", output.lower())
            self.assertIn("SHA-256", output)

    def test_bash_has_resume_retries_timeouts_and_plain_ci_mode(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        for marker in ("--continue-at", "--retry", "--connect-timeout", "--max-time"):
            self.assertIn(marker, content)
        self.assertIn("NO_COLOR", content)
        self.assertIn("CI", content)

    def test_bash_avoids_secret_environment_dump(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertNotRegex(content, r"\benv\b\s*\|\s*tee")
        self.assertNotIn("printenv", content)
        self.assertNotIn("set -x", content)


    def test_log_file_is_private_and_debug_does_not_dump_secrets(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_file = pathlib.Path(temp_dir) / "private.log"
            result = run_bash(
                "--install",
                "hermes",
                "--dry-run",
                "--non-interactive",
                "--skip-network-check",
                "--no-progress",
                "--debug",
                "--log-file",
                str(log_file),
                env={"OPENAI_API_KEY": "must-not-appear"},
            )
            output = decode(result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, output)
            self.assertEqual(log_file.stat().st_mode & 0o777, 0o600)
            self.assertNotIn("must-not-appear", log_file.read_text(encoding="utf-8"))



    @unittest.skipUnless(shutil.which("script"), "pseudo-terminal helper required")
    def test_noninteractive_tty_can_still_render_dynamic_progress(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            transcript = pathlib.Path(temp_dir) / "tty.out"
            log_file = pathlib.Path(temp_dir) / "tty.log"
            command = (
                "env -u CI INSTALLER_TEST_OS=linux INSTALLER_TEST_ARCH=x86_64 "
                "INSTALLER_TEST_DISTRO=kali bash ./install.sh --install cc-switch "
                "--dry-run --non-interactive --skip-network-check "
                f"--log-file {log_file}"
            )
            result = subprocess.run(
                ["script", "-qec", command, str(transcript)],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            output = decode(transcript.read_bytes()).replace("\r", "")
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("[########################] 100%", output)

    def test_github_proxy_credentials_are_redacted_from_output_and_log(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_file = pathlib.Path(temp_dir) / "proxy.log"
            result = run_bash(
                "--install",
                "cc-switch",
                "--dry-run",
                "--non-interactive",
                "--skip-network-check",
                "--no-progress",
                "--github-proxy",
                "https://user:supersecret@proxy.example/",
                "--log-file",
                str(log_file),
            )
            output = decode(result.stdout + result.stderr)
            log = log_file.read_text(encoding="utf-8")
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("supersecret", output)
            self.assertNotIn("supersecret", log)
            self.assertIn("https://***@proxy.example/", output + log)

    def test_bash_32_variable_boundaries_and_portable_find(self) -> None:
        import re

        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        unsafe = re.findall(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]", content)
        self.assertEqual(unsafe, [], f"Bash 3.2 may absorb UTF-8 bytes into variable names: {unsafe}")
        self.assertNotIn("-maxdepth", content)

    def test_powershell_has_progress_logging_and_official_sources(self) -> None:
        raw = (ROOT / "install.ps1").read_bytes()
        self.assertTrue(raw.startswith(b"\xef\xbb\xbf"))
        content = raw.decode("utf-8-sig")
        for option in ("[switch]$Quiet", "[switch]$NoProgress", "$LogFile", "[switch]$DebugInstaller"):
            self.assertIn(option, content)
        for url in (
            "https://claude.ai/install.ps1",
            "https://chatgpt.com/codex/install.ps1",
            "https://hermes-agent.nousresearch.com/install.ps1",
            "farion1231/cc-switch",
        ):
            self.assertIn(url, content)
        self.assertIn("Write-Progress", content)
        self.assertIn("SHA256", content)
        self.assertIn("ExitCode", content)

    def test_readme_documents_new_modes(self) -> None:
        content = (ROOT / "README.md").read_text(encoding="utf-8")
        for term in ("进度", "日志", "--no-progress", "--quiet", "--log-file", "Kali"):
            self.assertIn(term, content)

    def test_ci_has_real_kali_container_job(self) -> None:
        content = (ROOT / ".github/workflows/test.yml").read_text(encoding="utf-8")
        self.assertIn("kalilinux/kali-rolling", content)
        self.assertIn("container_matrix.sh", content)
        for runner in ("ubuntu-latest", "macos-latest", "windows-latest"):
            self.assertIn(runner, content)


if __name__ == "__main__":
    unittest.main()
