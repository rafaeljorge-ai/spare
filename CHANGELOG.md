# Changelog

All notable changes to this project are documented here. Format: Keep a Changelog. Versioning: SemVer.

## [Unreleased]

### Fixed
- Cleaner hardening: emptying the Trash now runs first, so it can never destroy an item the same run just moved there; a path listed twice is processed once; paths with `.` or `..` components are refused; project idleness is measured from the outermost project root; tools run with empty stdin and time limits (5 s lookup, 300 s command, injectable), a timeout ends the tool and reports the item as failed; the login shell lookup takes the last path line and can be injected, so tests never start a real shell.
- Homebrew cache is now deleted directly (`Library/Caches/Homebrew`, regenerable downloads) instead of running `brew cleanup --prune=all`, which also removes old versions of installed formulas.
- In-use detection no longer skips processes started through PATH (`node`, `cargo`, `npm`): their real path comes from `proc_pidpath`. Process listing has a 5 s timeout (`lsof -b -w`), a failed `ps` marks items that need the check as `unknown` instead of free, and `scriptName` skips interpreter flags.
- Project leftovers idleness: measured at the whole repository root (a `.git` directory or file above the artifact, inside the project root), so a monorepo package is idle only if the entire repo is. Creation dates and the artifact folder's own modification date also count as activity, covering unzipped or restored projects followed by an install.
- Safety guard hardening: user files refuse folders that contain protected or critical ones (`~/Library`, `~/Documents`, `~/Desktop`); `children` rules now enforce extensions and minimum age; project artifacts require their manifest and never enter `.git`; generic rules refuse paths owned by specific rules; hard links are tracked by device and inode.

### Added
- Cleaner with four actions: delete, move to the Trash (undoable), official tool command (once per rule) and empty the Trash. Right before each item it re-runs the safety guard, honors the scan's in-use flag (including `unknown`), checks running processes (one listing per run; a failed listing skips every item that needs the check) and, for project leftovers, re-measures idleness at the repository root. Anything that changed is skipped with a reason, never deleted. The scanner and the guard share one catalog and one clock (`environment.now`).
- `canTrashUserFile` refuses files inside `Library/Mail`, `Library/Messages` and `Library/Mobile Documents`.
- In-use detection: the scan lists the user's running processes once (`ps` plus the working directory from `lsof`) and sets `ScanItem.inUseBy` for items an app, tool or MCP server is using. An npx package counts as in use when a process names its folder in the command line or runs with it as working directory (symlink spellings such as `/var` and `/private/var` match). Official-command rules are never blocked, and a shell parked in a project folder does not block that project's artifacts.
- Approved visual prototype (`Prototype/run.sh`, mock data, no disk access) and design system in `.interface-design/system.md`: dark gradient, the Spare Ring, sidebar with colored tiles. Product principles recorded in the PRD: safe and visibly so, polished, light, intuitive.
- Idle project leftovers (`node_modules`, `.venv`, `.next`, `target`) in scans: only projects untouched for 30 days, manifest required next to the artifact, `.git` ignored, symlinks never followed. `live` environments use the conventional project roots (`Projetos`, `Projects`, `dev`, `Developer`, `code`).
- Walking skeleton: disk monitor, `spare status`, menu bar app showing free space, local gates and a minimal CI (secret scan and `.env` check on PRs, full gate on manual dispatch). CLI errors go to stderr.
- Rule catalog, safety guard and read-only scan (`spare scan`). Sizes never follow symlinks and count hard links once.
