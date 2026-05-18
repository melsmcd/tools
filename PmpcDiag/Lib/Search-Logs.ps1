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
        [psobject[]]$LogEntries,

        [string[]]$Keywords,

        [string[]]$Severities,

        [AllowNull()]
        [Nullable[datetime]]$After,

        [AllowNull()]
        [Nullable[datetime]]$Before
    )

    # Pre-compile a single combined regex for all keywords (case-insensitive).
    $keywordRegex = $null
    if ($Keywords -and $Keywords.Count -gt 0) {
        $combinedPattern = ($Keywords | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $keywordRegex = [regex]::new(
            $combinedPattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Compiled
        )
    }

    # HashSet membership is O(1) versus -in array's O(n) per entry.
    $severitySet = $null
    if ($Severities -and $Severities.Count -gt 0) {
        $severitySet = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$Severities,
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }

    $filtered = [System.Collections.Generic.List[psobject]]::new()

    foreach ($entry in $LogEntries) {
        if ($keywordRegex -and -not $keywordRegex.IsMatch([string]$entry.Message)) { continue }
        if ($severitySet -and -not $severitySet.Contains([string]$entry.Severity)) { continue }
        if ($After  -and (-not $entry.Timestamp -or $entry.Timestamp -lt $After))  { continue }
        if ($Before -and (-not $entry.Timestamp -or $entry.Timestamp -gt $Before)) { continue }
        $filtered.Add($entry)
    }

    $filtered | Sort-Object Timestamp
}
