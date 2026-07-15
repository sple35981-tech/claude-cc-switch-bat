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
UNIX_BASH_AVAILABLE = os.name != "nt" and BASH is not None


def decode(data: bytes) -> str:
    return data.decode("utf-8", errors="replace")


class InstallerTests(unittest.TestCase):
    def run_bash(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[bytes]:
        merged = os.environ.copy()
        merged.update(
            {
                "INSTALLER_TEST_OS": "linux",
                "INSTALLER_TEST_ARCH": "x86_64",
                "INSTALLER_TEST_DISTRO": "kali",
                "NO_COLOR": "1",
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

    @unittest.skipUnless(UNIX_BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_help_documents_progress_and_logging_options(self) -> None:
        result = self.run_bash("--help")
        output = decode(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, output)
        for option in ("--no-progress", "--quiet", "--log-file"):
            self.assertIn(option, output)

    @unittest.skipUnless(UNIX_BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_dry_run_all_has_truthful_stages_and_summary(self) -> None:
        result = self.run_bash("--install", "all", "--dry-run", "--skip-network-check", "--no-progress")
        output = decode(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, output)
        for stage in ("准备", "下载", "安装", "验证"):
            self.assertIn(stage, output)
        for name in ("Claude Code", "Codex CLI", "Hermes Agent", "CC Switch"):
            self.assertIn(name, output)
        self.assertIn("安装汇总", output)
        self.assertRegex(output, r"耗时: \d+ 秒")

    @unittest.skipUnless(UNIX_BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_non_tty_output_has_no_cursor_control_sequences(self) -> None:
        result = self.run_bash("--install", "codex", "--dry-run", "--skip-network-check")
        output = decode(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn("\r", output)
        self.assertNotRegex(output, r"\x1b\[[0-9;]*[A-Za-z]")

    @unittest.skipUnless(UNIX_BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_quiet_mode_keeps_summary_but_hides_info_noise(self) -> None:
        result = self.run_bash("--install", "codex", "--dry-run", "--skip-network-check", "--quiet")
        output = decode(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("安装汇总", output)
        self.assertNotIn("检测到:", output)

    @unittest.skipUnless(UNIX_BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_custom_log_is_created_and_proxy_credentials_are_redacted(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            log_path = pathlib.Path(td) / "installer.log"
            fake_bin = pathlib.Path(td) / "bin"
            fake_bin.mkdir()
            fake_curl = fake_bin / "curl"
            fake_curl.write_text(
                "#!/usr/bin/env bash\n"
                "out=''\nurl=''\n"
                "while [[ $# -gt 0 ]]; do case \"$1\" in -o) out=\"$2\"; shift 2;; http*) url=\"$1\"; shift;; *) shift;; esac; done\n"
                "cat > \"$out\" <<'EOF'\n#!/usr/bin/env bash\nmkdir -p \"$FAKE_INSTALL_BIN\"\nprintf '#!/usr/bin/env bash\\necho codex-test\\n' > \"$FAKE_INSTALL_BIN/codex\"\nchmod +x \"$FAKE_INSTALL_BIN/codex\"\nEOF\n"
                "exit 0\n",
                encoding="utf-8",
            )
            fake_curl.chmod(0o755)
            install_bin = pathlib.Path(td) / "installed"
            env = {
                "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
                "HOME": td,
                "FAKE_INSTALL_BIN": str(install_bin),
            }
            env["PATH"] = str(install_bin) + os.pathsep + env["PATH"]
            result = self.run_bash(
                "--install", "codex", "--non-interactive", "--skip-network-check",
                "--proxy", "http://alice:secret@127.0.0.1:7890",
                "--log-file", str(log_path), "--no-progress", env=env,
            )
            output = decode(result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, output)
            self.assertTrue(log_path.exists(), output)
            log = log_path.read_text(encoding="utf-8")
            self.assertIn("Codex CLI", log)
            self.assertNotIn("alice:secret", log)
            self.assertIn("***@127.0.0.1", log)

    @unittest.skipUnless(UNIX_BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_component_failure_continues_and_returns_nonzero(self) -> None:
        result = self.run_bash(
            "--install", "claude,codex", "--dry-run", "--skip-network-check", "--no-progress",
            env={"INSTALLER_TEST_FAIL_COMPONENT": "claude"},
        )
        output = decode(result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 0, output)
        self.assertIn("Claude Code", output)
        self.assertIn("失败阶段", output)
        self.assertIn("Codex CLI", output)
        self.assertIn("成功", output)

    def test_release_metadata_logs_cannot_pollute_asset_url(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertIn('download "$GITHUB_API_URL" "$json" "metadata"', content)
        self.assertIn('url="$(release_asset_url', content)
        self.assertIn("emit", content)
        self.assertNotRegex(content, r"release_asset_url\(\).*?log .*stdout", re.S)

    def test_bash_uses_only_official_sources(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        for source in (
            "https://claude.ai/install.sh",
            "https://chatgpt.com/codex/install.sh",
            "https://hermes-agent.nousresearch.com/install.sh",
            "farion1231/cc-switch",
        ):
            self.assertIn(source, content)
        self.assertNotRegex(content, r"(?m)^\s*(?:export\s+)?ANTHROPIC_AUTH_TOKEN=")
        self.assertNotRegex(content, r"(?m)^\s*(?:export\s+)?OPENAI_API_KEY=")

    def test_bash_32_compatibility_guards(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertNotIn("declare -A", content)
        self.assertNotIn("mapfile", content)
        self.assertNotIn("-maxdepth", content)
        unsafe = re.findall(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]", content)
        self.assertEqual(unsafe, [], unsafe)

    def test_powershell_has_progress_logging_and_utf8_bom(self) -> None:
        raw = (ROOT / "install.ps1").read_bytes()
        self.assertTrue(raw.startswith(b"\xef\xbb\xbf"))
        content = raw.decode("utf-8-sig")
        for token in (
            "[switch]$NoProgress",
            "[switch]$Quiet",
            "[string]$LogFile",
            "Write-Progress",
            "Write-InstallerLog",
            "Invoke-InstallerComponent",
            "https://chatgpt.com/codex/install.ps1",
            "https://hermes-agent.nousresearch.com/install.ps1",
        ):
            self.assertIn(token, content)

    def test_readmes_document_progress_logs_and_exit_status(self) -> None:
        for name in ("README.md", "README_EN.md"):
            content = (ROOT / name).read_text(encoding="utf-8")
            for token in ("--no-progress", "--log-file", "--quiet"):
                self.assertIn(token, content)
            self.assertRegex(content.lower(), r"log|日志")
            self.assertRegex(content.lower(), r"exit|退出")

    def test_ci_runs_container_matrix_and_three_platforms(self) -> None:
        content = (ROOT / ".github/workflows/test.yml").read_text(encoding="utf-8")
        for runner in ("ubuntu-latest", "macos-latest", "windows-latest"):
            self.assertIn(runner, content)
        self.assertIn("container_matrix.py", content)
        self.assertIn("-Install all", content)


if __name__ == "__main__":
    unittest.main()
