function Search-Logs {
    <#
    .SYNOPSIS
        Filters parsed log entries by keyword, severity, and date range.
    .PARAMETER LogEntries
        Array of PSCustomObjects from Read-CMTraceLog.
    .PARAMETER Keywords
        Keywords to match (case-insensitive). Entries matching ANY keyword are returned.
    .PARAMETER Severities
        Severity levels to include (Info, Warning, Error).
    .PARAMETER After
        Only return entries after this datetime.
    .PARAMETER Before
        Only return entries before this datetime.
    .OUTPUTS
        Filtered and sorted PSCustomObject array.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$LogEntries,

        [string[]]$Keywords,

        [string[]]$Severities,

        [AllowNull()]
        [Nullable[datetime]]$After,

        [AllowNull()]
        [Nullable[datetime]]$Before
    )

    $filtered = $LogEntries

    # Keyword filter — match any keyword (case-insensitive)
    if ($Keywords -and $Keywords.Count -gt 0) {
        $escapedKeywords = $Keywords | ForEach-Object { [regex]::Escape($_) }
        $combinedPattern = $escapedKeywords -join '|'

        $filtered = $filtered | Where-Object {
            $_.Message -match $combinedPattern
        }
    }

    # Severity filter
    if ($Severities -and $Severities.Count -gt 0) {
        $filtered = $filtered | Where-Object {
            $_.Severity -in $Severities
        }
    }

    # Date range filters
    if ($After) {
        $filtered = $filtered | Where-Object {
            $_.Timestamp -and $_.Timestamp -ge $After
        }
    }

    if ($Before) {
        $filtered = $filtered | Where-Object {
            $_.Timestamp -and $_.Timestamp -le $Before
        }
    }

    # Sort by timestamp
    $filtered | Sort-Object Timestamp
}
