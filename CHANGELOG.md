# Changelog

All notable changes to this project are documented here. Format: Keep a Changelog. Versioning: SemVer.

## [Unreleased]

### Fixed
- Safety guard hardening: user files refuse folders that contain protected or critical ones (`~/Library`, `~/Documents`, `~/Desktop`); `children` rules now enforce extensions and minimum age; project artifacts require their manifest and never enter `.git`; generic rules refuse paths owned by specific rules; hard links are tracked by device and inode.

### Added
- Idle project leftovers (`node_modules`, `.venv`, `.next`, `target`) in scans: only projects untouched for 30 days, manifest required next to the artifact, `.git` ignored, symlinks never followed. `live` environments use the conventional project roots (`Projetos`, `Projects`, `dev`, `Developer`, `code`).
- Walking skeleton: disk monitor, `spare status`, menu bar app showing free space, local gates and a minimal CI (secret scan and `.env` check on PRs, full gate on manual dispatch). CLI errors go to stderr.
- Rule catalog, safety guard and read-only scan (`spare scan`). Sizes never follow symlinks and count hard links once.
