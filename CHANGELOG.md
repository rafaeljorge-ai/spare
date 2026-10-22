# Changelog

All notable changes to this project are documented here. Format: Keep a Changelog. Versioning: SemVer.

## [Unreleased]

### Fixed
- Project leftovers idleness: measured at the whole repository root (a `.git` directory or file above the artifact, inside the project root), so a monorepo package is idle only if the entire repo is. Creation dates and the artifact folder's own modification date also count as activity, covering unzipped or restored projects followed by an install.
- Safety guard hardening: user files refuse folders that contain protected or critical ones (`~/Library`, `~/Documents`, `~/Desktop`); `children` rules now enforce extensions and minimum age; project artifacts require their manifest and never enter `.git`; generic rules refuse paths owned by specific rules; hard links are tracked by device and inode.

### Added
- In-use detection: the scan lists the user's running processes once (`ps` plus the working directory from `lsof`) and sets `ScanItem.inUseBy` for items an app, tool or MCP server is using. An npx package counts as in use when a process names its folder in the command line or runs with it as working directory (symlink spellings such as `/var` and `/private/var` match). Official-command rules are never blocked, and a shell parked in a project folder does not block that project's artifacts.
- Approved visual prototype (`Prototype/run.sh`, mock data, no disk access) and design system in `.interface-design/system.md`: dark gradient, the Spare Ring, sidebar with colored tiles. Product principles recorded in the PRD: safe and visibly so, polished, light, intuitive.
- Idle project leftovers (`node_modules`, `.venv`, `.next`, `target`) in scans: only projects untouched for 30 days, manifest required next to the artifact, `.git` ignored, symlinks never followed. `live` environments use the conventional project roots (`Projetos`, `Projects`, `dev`, `Developer`, `code`).
- Walking skeleton: disk monitor, `spare status`, menu bar app showing free space, local gates and a minimal CI (secret scan and `.env` check on PRs, full gate on manual dispatch). CLI errors go to stderr.
- Rule catalog, safety guard and read-only scan (`spare scan`). Sizes never follow symlinks and count hard links once.
