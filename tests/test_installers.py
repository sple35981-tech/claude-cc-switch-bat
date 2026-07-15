from __future__ import annotations

import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")


def decode(data: bytes) -> str:
    return data.decode("utf-8", errors="replace")


class InstallerTests(unittest.TestCase):
    maxDiff = None

    def run_bash(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[bytes]:
        self.assertIsNotNone(BASH)
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
            [BASH, str(ROOT / "install.sh"), *args],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=merged,
            check=False,
        )

    def test_bash_help_documents_detailed_output_options(self) -> None:
        result = self.run_bash("--help")
        output = decode(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, output)
        for flag in ("--quiet", "--no-progress", "--log-file", "--debug", "--keep-temp"):
            self.assertIn(flag, output)

    def test_bash_no_tty_dry_run_has_stable_progress_and_log(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            log_path = pathlib.Path(td) / "installer.log"
            result = self.run_bash(
                "--install",
                "all",
                "--dry-run",
                "--non-interactive",
                "--skip-network-check",
                "--log-file",
                str(log_path),
            )
            output = decode(result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("AI CLI Installer Collector", output)
            self.assertRegex(output, r"\[STEP \d+/\d+\]")
            self.assertIn("100%", output)
            self.assertNotIn("\r", output)
            self.assertTrue(log_path.exists())
            log = log_path.read_text(encoding="utf-8")
            self.assertIn("OS=linux", log)
            self.assertIn("DISTRO=kali", log)
            for name in ("Claude Code", "Codex CLI", "Hermes Agent", "CC Switch"):
                self.assertIn(name, log)

    def test_bash_quiet_mode_keeps_complete_log(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            log_path = pathlib.Path(td) / "quiet.log"
            result = self.run_bash(
                "--install",
                "codex",
                "--dry-run",
                "--non-interactive",
                "--skip-network-check",
                "--quiet",
                "--log-file",
                str(log_path),
            )
            self.assertEqual(result.returncode, 0, decode(result.stderr))
            self.assertEqual(decode(result.stdout), "")
            log = log_path.read_text(encoding="utf-8")
            self.assertIn("Codex CLI", log)
            self.assertIn("Dry-run", log)

    def test_bash_log_is_private_and_redacts_credentials(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            log_path = pathlib.Path(td) / "secure.log"
            result = self.run_bash(
                "--install", "codex", "--dry-run", "--non-interactive",
                "--skip-network-check", "--proxy",
                "http://alice:secret@127.0.0.1:7890",
                "--log-file", str(log_path),
            )
            output = decode(result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, output)
            log = log_path.read_text(encoding="utf-8")
            self.assertNotIn("alice:secret", log)
            self.assertIn("***@127.0.0.1", log)
            self.assertEqual(log_path.stat().st_mode & 0o077, 0)

    def test_bash_failure_continues_and_returns_nonzero(self) -> None:
        result = self.run_bash(
            "--install",
            "claude,codex",
            "--dry-run",
            "--non-interactive",
            "--skip-network-check",
            env={"INSTALLER_TEST_FAIL_COMPONENT": "claude"},
        )
        output = decode(result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 0, output)
        self.assertIn("Claude Code", output)
        self.assertIn("失败", output)
        self.assertIn("Codex CLI", output)
        self.assertIn("成功", output)
        self.assertIn("100%", output)

    def test_bash_uses_resilient_download_and_url_assignment(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertIn("--retry-all-errors", content)
        self.assertIn("--continue-at", content)
        self.assertIn("--progress-bar", content)
        self.assertIn("CC_SWITCH_ASSET_URL=", content)
        self.assertNotRegex(content, r'url="\$\(release_asset_url')

    def test_bash_uses_official_sources_and_four_phase_lifecycle(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        for url in (
            "https://claude.ai/install.sh",
            "https://chatgpt.com/codex/install.sh",
            "https://hermes-agent.nousresearch.com/install.sh",
            "farion1231/cc-switch",
        ):
            self.assertIn(url, content)
        for phase in ("准备", "下载", "安装", "验证"):
            self.assertIn(phase, content)
        self.assertNotIn("ANTHROPIC_AUTH_TOKEN=", content)
        self.assertNotIn("OPENAI_API_KEY=", content)

    def test_bash_32_variable_boundaries_are_safe(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        unsafe = re.findall(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]", content)
        self.assertEqual(unsafe, [], f"Bash 3.2 may absorb UTF-8 bytes into variable names: {unsafe}")

    def test_powershell_has_progress_logging_and_utf8_bom(self) -> None:
        raw = (ROOT / "install.ps1").read_bytes()
        self.assertTrue(raw.startswith(b"\xef\xbb\xbf"))
        content = raw.decode("utf-8-sig")
        for token in (
            "[switch]$Quiet",
            "[switch]$NoProgress",
            "[string]$LogFile",
            "Write-Progress",
        ):
            self.assertIn(token, content)
        self.assertRegex(content, r"Write-(?:Installer)?Log")
        self.assertRegex(content, r"Invoke-(?:Installer)?Component")
        for url in (
            "https://claude.ai/install.ps1",
            "https://chatgpt.com/codex/install.ps1",
            "https://hermes-agent.nousresearch.com/install.ps1",
            "farion1231/cc-switch",
        ):
            self.assertIn(url, content)

    def test_cmd_wrapper_forwards_arguments(self) -> None:
        content = (ROOT / "install.cmd").read_text(encoding="utf-8").lower()
        self.assertIn("powershell", content)
        self.assertIn("install.ps1", content)
        self.assertIn("%*", content)

    def test_container_matrix_script_covers_requested_platforms(self) -> None:
        content = (ROOT / "tests" / "container_matrix.sh").read_text(encoding="utf-8")
        for platform in ("kali", "debian", "fedora", "arch", "macos", "no-tty", "failure"):
            self.assertIn(platform, content)

    def test_ci_runs_container_matrix(self) -> None:
        content = (ROOT / ".github" / "workflows" / "test.yml").read_text(encoding="utf-8")
        self.assertIn("tests/container_matrix.sh", content)
        for runner in ("ubuntu-latest", "macos-latest", "windows-latest"):
            self.assertIn(runner, content)


if __name__ == "__main__":
    unittest.main()
