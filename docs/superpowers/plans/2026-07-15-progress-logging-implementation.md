# Installer Progress and Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add truthful staged progress, detailed logs, elapsed-time summaries, and container-style platform validation to both installers.

**Architecture:** Keep each platform installer self-contained. A small progress/logging layer wraps the existing component installers, while tests invoke the real scripts with fake commands and platform environment variables. Interactive rendering degrades automatically to line output outside a TTY.

**Tech Stack:** Bash 3.2+, Windows PowerShell 5.1+, Python unittest, GitHub Actions.

## Global Constraints

- Preserve all official upstream install URLs.
- Add no runtime dependencies.
- Never log credentials or proxy userinfo.
- Continue after individual component failures and return non-zero at the end.
- Preserve existing CLI compatibility.

---

### Task 1: Progress and logging contract

**Files:**
- Modify: `tests/test_installers.py`
- Modify: `install.sh`
- Modify: `install.ps1`

- [ ] Add failing tests for new options, progress stages, elapsed time, default/custom logs, redaction, and non-TTY output.
- [ ] Run the focused tests and confirm failures are feature-related.
- [ ] Implement shared stage accounting and log functions in both scripts.
- [ ] Run focused and full tests.

### Task 2: Download and component stage integration

**Files:**
- Modify: `install.sh`
- Modify: `install.ps1`
- Modify: `tests/test_installers.py`

- [ ] Add failing executable tests for CC Switch metadata/download separation, downloader progress flags, and failure-stage summaries.
- [ ] Integrate prepare/download/install/verify stage updates into all four component installers.
- [ ] Verify a failed component does not block later components and final exit is non-zero.

### Task 3: Platform sandbox matrix

**Files:**
- Create: `tests/container_matrix.py`
- Modify: `.github/workflows/test.yml`

- [ ] Build fake command sandboxes for apt, dnf, rpm, AppImage, brew, and macOS ZIP paths.
- [ ] Run Kali, Debian, Fedora, Arch, macOS, non-TTY, and injected-failure cases.
- [ ] Add the matrix to GitHub Actions and retain Windows PowerShell validation.

### Task 4: Documentation and final verification

**Files:**
- Modify: `README.md`
- Modify: `README_EN.md`

- [ ] Document interactive progress, log paths, quiet/no-progress modes, exit semantics, and troubleshooting.
- [ ] Run unit tests, sandbox matrix, Bash syntax, dry-run matrix, unsafe-source scan, and credentials scan.
- [ ] Publish a PR, require Ubuntu/macOS/Windows CI success, and merge.
