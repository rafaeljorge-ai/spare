# Security

## What Spare can delete

Spare can remove files inside your home folder, and only:

- paths listed in its rule catalog (caches, logs, downloaded installers and models, old runtimes);
- idle project folders (`node_modules`, `.venv`, `.next`, `target`) inside the project folders you configure;
- files you explicitly pick on the Largest files screen (moved to the Trash).

Anything that cannot be regenerated goes to the Trash with its location recorded, so Undo works. Emptying the system Trash is the only permanent removal and needs explicit confirmation.

## Invariants

1. Closed catalog: items outside the catalog or your project folders are refused.
2. Symbolic links are never followed outside a rule's path.
3. Protected paths are never targets: anything outside the home folder, system folders, Documents, Desktop, Pictures, Movies, Music, the `~/Library` root, `.ssh`, `.gnupg`, `.aws`, `.kube`, Keychains and iCloud Drive.
4. Items in use are skipped.
5. Project folders are listed only when idle and with their manifest file.
6. Delete only what regenerates; the rest goes to the Trash or uses the tool's official cleanup command.
7. Emptying the Trash requires explicit confirmation.
8. A project folder inside a protected place (for example `~/Documents`) is never listed or cleaned, even when you configure it as a project folder.
9. A throwaway home (`SPARE_HOME`) never reaches your real Trash or your real tool caches.
10. Quitting a process: only the current user's processes, never PID 1, system processes or Spare itself, and never `SIGKILL`.

## Reporting a vulnerability

Please report privately through GitHub Security Advisories on `rafaeljorge-ai/spare` (Security tab, "Report a vulnerability"). Do not open a public issue for security problems.
