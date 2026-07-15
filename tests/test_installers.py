from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASH_AVAILABLE = os.name != "nt" and shutil.which("bash") is not None


def configure_utf8_locale(env: dict[str, str]) -> None:
    locale_name = "en_US.UTF-8" if sys.platform == "darwin" else "C.UTF-8"
    env["LANG"] = locale_name
    env["LC_ALL"] = locale_name


class InstallerRepositoryTests(unittest.TestCase):
    def run_bash(self, *args: str, env_updates: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        configure_utf8_locale(env)
        env.update(
            {
                "INSTALLER_TEST_OS": "linux",
                "INSTALLER_TEST_ARCH": "x86_64",
                "INSTALLER_TEST_DISTRO": "debian",
                "INSTALLER_FAKE_ASSET_URL": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.deb",
            }
        )
        if env_updates:
            env.update(env_updates)
        return subprocess.run(
            ["bash", str(ROOT / "install.sh"), *args],
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_installer_has_valid_syntax(self) -> None:
        script = ROOT / "install.sh"
        self.assertTrue(script.exists(), "install.sh must exist")
        result = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_help_documents_collector_options(self) -> None:
        result = self.run_bash("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        for option in (
            "--install",
            "--channel",
            "--proxy",
            "--github-proxy",
            "--dry-run",
            "--skip-claude",
            "--skip-cc-switch",
        ):
            self.assertIn(option, result.stdout)
        for component in ("claude", "codex", "hermes", "cc-switch", "all"):
            self.assertIn(component, result.stdout.lower())

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_selects_only_codex_and_hermes(self) -> None:
        result = self.run_bash(
            "--install",
            "codex,hermes",
            "--dry-run",
            "--non-interactive",
            "--skip-network-check",
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("https://chatgpt.com/codex/install.sh", output)
        self.assertIn("https://hermes-agent.nousresearch.com/install.sh", output)
        self.assertNotIn("https://claude.ai/install.sh", output)
        self.assertNotIn("CC Switch 来源", output)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_install_all_uses_four_official_sources(self) -> None:
        result = self.run_bash(
            "--install",
            "all",
            "--dry-run",
            "--non-interactive",
            "--skip-network-check",
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("https://claude.ai/install.sh", output)
        self.assertIn("https://chatgpt.com/codex/install.sh", output)
        self.assertIn("https://hermes-agent.nousresearch.com/install.sh", output)
        self.assertIn("farion1231/cc-switch", output)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_menu_selection_can_be_simulated(self) -> None:
        result = self.run_bash(
            "--dry-run",
            "--skip-network-check",
            env_updates={"INSTALLER_TEST_SELECTION": "2,3"},
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("Codex", output)
        self.assertIn("Hermes", output)
        self.assertNotIn("Anthropic 官方", output)
        self.assertNotIn("CC Switch 来源", output)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_noninteractive_default_preserves_legacy_pair(self) -> None:
        result = self.run_bash(
            "--dry-run",
            "--non-interactive",
            "--skip-network-check",
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("https://claude.ai/install.sh", output)
        self.assertIn("farion1231/cc-switch", output)
        self.assertNotIn("https://chatgpt.com/codex/install.sh", output)
        self.assertNotIn("https://hermes-agent.nousresearch.com/install.sh", output)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_rejects_unknown_component(self) -> None:
        result = self.run_bash("--install", "claude,unknown", "--dry-run", "--skip-network-check")
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown", output.lower())
        self.assertIn("claude", output.lower())

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_component_failure_does_not_stop_remaining_components(self) -> None:
        result = self.run_bash(
            "--install",
            "codex,hermes",
            "--dry-run",
            "--non-interactive",
            "--skip-network-check",
            env_updates={"INSTALLER_TEST_FAIL_COMPONENT": "codex"},
        )
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, output)
        self.assertIn("Codex", output)
        self.assertIn("Hermes", output)
        self.assertIn("Codex CLI", output)
        self.assertIn("成功", output)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_dry_run_works_without_release_fixture(self) -> None:
        env = {
            "INSTALLER_TEST_OS": "linux",
            "INSTALLER_TEST_ARCH": "x86_64",
            "INSTALLER_TEST_DISTRO": "debian",
            "INSTALLER_FAKE_ASSET_URL": "",
        }
        result = self.run_bash(
            "--install",
            "cc-switch",
            "--dry-run",
            "--skip-network-check",
            env_updates=env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("releases/latest/download", result.stdout + result.stderr)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_appimage_dry_run_does_not_download_twice(self) -> None:
        result = self.run_bash(
            "--install",
            "cc-switch",
            "--dry-run",
            "--skip-network-check",
            env_updates={
                "INSTALLER_TEST_ARCH": "arm64",
                "INSTALLER_TEST_DISTRO": "arch",
                "INSTALLER_FAKE_ASSET_URL": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-arm64.AppImage",
            },
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertEqual(output.count("下载:"), 1, output)
        self.assertIn("~/.local/bin", output.replace(str(pathlib.Path.home()), "~"))

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_without_tty_falls_back_to_legacy_pair(self) -> None:
        env = os.environ.copy()
        configure_utf8_locale(env)
        env.update(
            {
                "INSTALLER_TEST_OS": "linux",
                "INSTALLER_TEST_ARCH": "x86_64",
                "INSTALLER_TEST_DISTRO": "debian",
                "INSTALLER_FAKE_ASSET_URL": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.deb",
            }
        )
        env.pop("INSTALLER_TEST_SELECTION", None)
        result = subprocess.run(
            ["bash", str(ROOT / "install.sh"), "--dry-run", "--skip-network-check"],
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("兼容默认选择", output)
        self.assertIn("https://claude.ai/install.sh", output)
        self.assertIn("farion1231/cc-switch", output)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_real_codex_path_survives_network_check_when_other_components_unselected(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as temp_dir:
            fake_bin = pathlib.Path(temp_dir)
            fake_curl = fake_bin / "curl"
            fake_curl.write_text(
                """#!/usr/bin/env bash
set -e
out=''
while [[ $# -gt 0 ]]; do
  case \"$1\" in
    -o) out=\"$2\"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n \"$out\" ]]; then
  printf '#!/bin/sh\\nexit 0\\n' > \"$out\"
fi
exit 0
""",
                encoding="utf-8",
            )
            fake_curl.chmod(0o755)
            env = os.environ.copy()
            configure_utf8_locale(env)
            env.update(
                {
                    "PATH": str(fake_bin) + os.pathsep + env["PATH"],
                    "INSTALLER_TEST_OS": "linux",
                    "INSTALLER_TEST_ARCH": "x86_64",
                    "INSTALLER_TEST_DISTRO": "debian",
                }
            )
            result = subprocess.run(
                ["bash", str(ROOT / "install.sh"), "--install", "codex", "--non-interactive"],
                env=env,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                check=False,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("Codex CLI: 成功", output)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_rejects_invalid_channel(self) -> None:
        result = self.run_bash("--channel", "nightly")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stable", result.stderr + result.stdout)

    def test_bash_guards_empty_selected_array_for_bash_32(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertIn('[[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]] && return 1', content)

    def test_windows_installer_has_utf8_bom_for_powershell_51(self) -> None:
        content = (ROOT / "install.ps1").read_bytes()
        self.assertTrue(content.startswith(b"\xef\xbb\xbf"), "Windows PowerShell 5.1 requires a UTF-8 BOM for non-ASCII scripts")

    def test_bash_uses_macos_portable_find(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertNotIn("-maxdepth", content)

    def test_windows_installer_uses_all_official_sources_and_safe_msi(self) -> None:
        content = (ROOT / "install.ps1").read_text(encoding="utf-8")
        self.assertIn("https://claude.ai/install.ps1", content)
        self.assertIn("https://chatgpt.com/codex/install.ps1", content)
        self.assertIn("https://hermes-agent.nousresearch.com/install.ps1", content)
        self.assertIn("farion1231/cc-switch", content)
        self.assertIn("msiexec.exe", content)
        self.assertIn("ValidateSet('stable', 'latest')", content)
        self.assertIn("[string[]]$Install", content)
        self.assertIn("Read-Host", content)
        self.assertIn("Invoke-Component", content)
        self.assertIn("Get-RestMethodParameters", content)
        self.assertIn('`"$msiPath`"', content)
        self.assertNotIn("ANTHROPIC_AUTH_TOKEN=", content)
        self.assertNotIn("OPENAI_API_KEY=", content)

    def test_cmd_wrapper_invokes_powershell(self) -> None:
        content = (ROOT / "install.cmd").read_text(encoding="utf-8").lower()
        self.assertIn("powershell", content)
        self.assertIn("install.ps1", content)
        self.assertIn("%*", content)

    def test_readme_documents_four_tool_collector(self) -> None:
        content = (ROOT / "README.md").read_text(encoding="utf-8")
        for name in ("Claude Code", "Codex", "Hermes", "CC Switch"):
            self.assertIn(name, content)
        self.assertIn("--install", content)
        self.assertIn("-Install", content)
        self.assertIn("交互", content)
        self.assertIn("中国", content)
        self.assertIn("代理", content)

    def test_ci_matrix_covers_three_platforms_and_all_components(self) -> None:
        content = (ROOT / ".github/workflows/test.yml").read_text(encoding="utf-8")
        for runner in ("ubuntu-latest", "macos-latest", "windows-latest"):
            self.assertIn(runner, content)
        self.assertIn("unittest", content)
        self.assertIn("--install all", content)
        self.assertIn("-Install all", content)


if __name__ == "__main__":
    unittest.main()
