# tools

Melissa's cool tools repository!

## PmpcDiag — Patch My PC Intune Log Troubleshooter

A WPF desktop tool that parses Patch My PC and Intune Management Extension (IME) logs, searches by keyword, and displays results in a sortable grid with a detail view.

### Requirements

- Windows with PowerShell 5.1 or later
- Read access to the log directories (typically under `C:\ProgramData\`). An elevated PowerShell session is recommended.

### Default log locations

When no custom path is provided, the tool auto-discovers these files:

- **Patch My PC:** `C:\ProgramData\PatchMyPCIntuneLogs\*.log` and `C:\ProgramData\PatchMyPC\PatchMyPC-*.log`
- **IME:** `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\` (AgentExecutor, IntuneManagementExtension, AppWorkload)

### How to run

1. Open PowerShell (run as Administrator if your logs are in protected locations).
2. Change into the tool directory:
   ```powershell
   cd C:\path\to\tools\PmpcDiag
   ```
3. If scripts are blocked by execution policy, allow the script for this session only:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
4. Launch the UI:
   ```powershell
   .\PmpcDiag.ps1
   ```

One-liner equivalent:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\PmpcDiag\PmpcDiag.ps1
```

### Using the UI

- **Keywords:** comma-separated terms to match against log messages. Leave blank to return all entries that pass the other filters.
- **Include default keywords:** adds a curated list of known PMPC/IME error terms to the search.
- **Log set:** All, Patch My PC only, or IME only.
- **Severity:** Error / Warning / Info checkboxes.
- **Date range:** optional After / Before filters.
- **Log path:** leave blank to auto-discover, or use **Browse** to point at any folder containing `.log` files.
- **Search:** parses the selected logs and populates the results grid (press Enter in the keyword box to search).
- **Export CSV:** saves the current results to a timestamped CSV.
- Select a row to see the full message and source file path in the detail pane.
