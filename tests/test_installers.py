from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


BASH_AVAILABLE = os.name != "nt" and shutil.which("bash") is not None


class InstallerRepositoryTests(unittest.TestCase):
    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_installer_has_valid_syntax(self) -> None:
        script = ROOT / "install.sh"
        self.assertTrue(script.exists(), "install.sh must exist")
        result = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_help_documents_core_options(self) -> None:
        result = subprocess.run(
            ["bash", str(ROOT / "install.sh"), "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for option in ("--channel", "--proxy", "--github-proxy", "--dry-run", "--skip-claude", "--skip-cc-switch"):
            self.assertIn(option, result.stdout)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_linux_dry_run_uses_official_sources(self) -> None:
        env = os.environ.copy()
        env.update(
            {
                "INSTALLER_TEST_OS": "linux",
                "INSTALLER_TEST_ARCH": "x86_64",
                "INSTALLER_TEST_DISTRO": "debian",
                "INSTALLER_FAKE_RELEASE_TAG": "v9.9.9",
                "INSTALLER_FAKE_ASSET_URL": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-x86_64.deb",
            }
        )
        result = subprocess.run(
            [
                "bash",
                str(ROOT / "install.sh"),
                "--dry-run",
                "--non-interactive",
                "--skip-network-check",
            ],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        output = result.stdout + result.stderr
        self.assertIn("https://claude.ai/install.sh", output)
        self.assertIn("farion1231/cc-switch", output)
        self.assertIn("CC-Switch-v9.9.9-Linux-x86_64.deb", output)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_dry_run_works_without_release_fixture(self) -> None:
        env = os.environ.copy()
        env.update(
            {
                "INSTALLER_TEST_OS": "linux",
                "INSTALLER_TEST_ARCH": "x86_64",
                "INSTALLER_TEST_DISTRO": "debian",
            }
        )
        env.pop("INSTALLER_FAKE_ASSET_URL", None)
        result = subprocess.run(
            ["bash", str(ROOT / "install.sh"), "--dry-run", "--skip-network-check"],
            env=env, capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("releases/latest/download", result.stdout + result.stderr)

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_appimage_dry_run_does_not_download_twice(self) -> None:
        env = os.environ.copy()
        env.update(
            {
                "INSTALLER_TEST_OS": "linux",
                "INSTALLER_TEST_ARCH": "arm64",
                "INSTALLER_TEST_DISTRO": "arch",
                "INSTALLER_FAKE_ASSET_URL": "https://github.com/farion1231/cc-switch/releases/download/v9.9.9/CC-Switch-v9.9.9-Linux-arm64.AppImage",
            }
        )
        result = subprocess.run(
            ["bash", str(ROOT / "install.sh"), "--dry-run", "--skip-network-check", "--skip-claude"],
            env=env, capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        output = result.stdout + result.stderr
        self.assertEqual(output.count("下载:"), 1, output)
        self.assertIn("~/.local/bin", output.replace(str(pathlib.Path.home()), "~"))

    @unittest.skipUnless(BASH_AVAILABLE, "Bash execution tests require a Unix-like runner")
    def test_bash_rejects_invalid_channel(self) -> None:
        result = subprocess.run(
            ["bash", str(ROOT / "install.sh"), "--channel", "nightly"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stable", result.stderr + result.stdout)

    def test_bash_uses_macos_portable_find(self) -> None:
        content = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertNotIn("-maxdepth", content)

    def test_windows_installer_uses_official_sources_and_safe_msi(self) -> None:
        content = (ROOT / "install.ps1").read_text(encoding="utf-8")
        self.assertIn("https://claude.ai/install.ps1", content)
        self.assertIn("farion1231/cc-switch", content)
        self.assertIn("msiexec.exe", content)
        self.assertIn("ValidateSet('stable', 'latest')", content)
        self.assertIn("DryRun", content)
        self.assertIn("Get-RestMethodParameters", content)
        self.assertIn('`"$msiPath`"', content)
        self.assertNotIn("ANTHROPIC_AUTH_TOKEN=", content)

    def test_cmd_wrapper_invokes_powershell(self) -> None:
        content = (ROOT / "install.cmd").read_text(encoding="utf-8").lower()
        self.assertIn("powershell", content)
        self.assertIn("install.ps1", content)
        self.assertIn("%*", content)

    def test_readme_contains_quick_start_and_china_network_guidance(self) -> None:
        content = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("一键安装", content)
        self.assertIn("install.ps1", content)
        self.assertIn("install.sh", content)
        self.assertIn("中国", content)
        self.assertIn("代理", content)
        self.assertIn("farion1231/cc-switch", content)

    def test_ci_matrix_covers_three_platforms(self) -> None:
        content = (ROOT / ".github/workflows/test.yml").read_text(encoding="utf-8")
        for runner in ("ubuntu-latest", "macos-latest", "windows-latest"):
            self.assertIn(runner, content)
        self.assertIn("unittest", content)


if __name__ == "__main__":
    unittest.main()
