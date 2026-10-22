# Changelog

All notable changes to this project are documented here. Format: Keep a Changelog. Versioning: SemVer.

## [Unreleased]

### Added
- Walking skeleton: disk monitor, `spare status`, menu bar app showing free space, local gates and a minimal CI (secret scan and `.env` check on PRs, full gate on manual dispatch). CLI errors go to stderr.
- Rule catalog, safety guard and read-only scan (`spare scan`). Sizes never follow symlinks and count hard links once.
