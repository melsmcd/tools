function Get-LogPaths {
    <#
    .SYNOPSIS
        Resolves and returns Intune log file paths for Patch My PC troubleshooting.
    .PARAMETER LogSet
        Which log group to return: All, PatchMyPC, or IME.
    .OUTPUTS
        System.IO.FileInfo[] of existing log files.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('All', 'PatchMyPC', 'IME')]
        [string]$LogSet = 'All'
    )

    $programData = $env:ProgramData
    $results = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    # --- PatchMyPC logs ---
    if ($LogSet -eq 'All' -or $LogSet -eq 'PatchMyPC') {
        $pmpcIntuneLogs = @(
            "$programData\PatchMyPCIntuneLogs\PatchMyPC-ScriptRunner.log",
            "$programData\PatchMyPCIntuneLogs\PatchMyPC-SoftwareDetectionScript.log",
            "$programData\PatchMyPCIntuneLogs\PatchMyPC-SoftwareUpdateDetectionScript.log"
        )

        foreach ($logPath in $pmpcIntuneLogs) {
            if (Test-Path -LiteralPath $logPath) {
                $results.Add([System.IO.FileInfo]::new($logPath))
            }
            else {
                $warnings.Add("Not found: $logPath")
            }
        }

        # ScriptRunner may also be in PatchMyPC dir (Company Portal installs)
        $altScriptRunner = "$programData\PatchMyPC\PatchMyPC-ScriptRunner.log"
        if (Test-Path -LiteralPath $altScriptRunner) {
            # Only add if not already found in PatchMyPCIntuneLogs
            $alreadyFound = $results | Where-Object { $_.Name -eq 'PatchMyPC-ScriptRunner.log' }
            if (-not $alreadyFound) {
                $results.Add([System.IO.FileInfo]::new($altScriptRunner))
            }
        }

        # UserNotification log
        $userNotif = "$programData\PatchMyPC\PatchMyPC-UserNotification.log"
        if (Test-Path -LiteralPath $userNotif) {
            $results.Add([System.IO.FileInfo]::new($userNotif))
        }
        else {
            $warnings.Add("Not found: $userNotif")
        }
    }

    # --- IME (Intune Management Extension) logs ---
    if ($LogSet -eq 'All' -or $LogSet -eq 'IME') {
        $imeLogDir = "$programData\Microsoft\IntuneManagementExtension\Logs"

        if (Test-Path -LiteralPath $imeLogDir) {
            $wildcards = @('AgentExecutor*.log', 'IntuneManagementExtension*.log', 'AppWorkload*.log')

            foreach ($wc in $wildcards) {
                $found = Get-ChildItem -Path $imeLogDir -Filter $wc -File -ErrorAction SilentlyContinue
                if ($found) {
                    foreach ($f in $found) { $results.Add($f) }
                }
                else {
                    $warnings.Add("No files matching '$wc' in $imeLogDir")
                }
            }
        }
        else {
            $warnings.Add("IME log directory not found: $imeLogDir")
        }
    }

    # Emit warnings
    foreach ($w in $warnings) {
        Write-Warning $w
    }

    return $results.ToArray()
}
