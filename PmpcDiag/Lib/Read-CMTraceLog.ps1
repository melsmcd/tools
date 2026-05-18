# Compile the CMTrace regex once and reuse across calls.
# Format: <![LOG[message]LOG]!><time="HH:mm:ss.fffffff+offset" date="M-DD-YYYY" component="..." context="" type="N" thread="N" file="">
$script:CMTraceRegex = [regex]::new(
    '<!\[LOG\[(?<msg>.*?)\]LOG\]!>.*?time="(?<time>[\d:.+\-]+).*?".*?date="(?<date>[\d-]+)".*?component="(?<component>[^"]*)".*?type="(?<type>\d)"',
    [System.Text.RegularExpressions.RegexOptions]::SingleLine -bor [System.Text.RegularExpressions.RegexOptions]::Compiled
)

$script:CMTraceSeverityMap = @{ '1' = 'Info'; '2' = 'Warning'; '3' = 'Error' }

function Read-CMTraceLog {
    <#
    .SYNOPSIS
        Parses a CMTrace-formatted log file into structured objects.
    .PARAMETER Path
        Full path to the CMTrace log file.
    .OUTPUTS
        PSCustomObject with Timestamp, Message, Severity, Component, Source, FullPath, LineNumber.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $fileName = [System.IO.Path]::GetFileName($Path)
    $content  = [System.IO.File]::ReadAllText($Path)

    $regexMatches = $script:CMTraceRegex.Matches($content)
    if ($regexMatches.Count -eq 0) { return }

    # Pre-compute newline positions so per-match line numbers are O(log n) instead of O(filesize).
    $newlinePositions = [System.Collections.Generic.List[int]]::new()
    $scanIdx = 0
    while (($scanIdx = $content.IndexOf("`n", $scanIdx)) -ge 0) {
        $newlinePositions.Add($scanIdx)
        $scanIdx++
    }

    # Matches arrive in ascending Index order — walk newlines with a running pointer.
    $nlCount = $newlinePositions.Count
    $nlPtr   = 0

    $results = [System.Collections.Generic.List[psobject]]::new($regexMatches.Count)

    foreach ($m in $regexMatches) {
        $rawTime   = $m.Groups['time'].Value
        $rawDate   = $m.Groups['date'].Value
        $message   = $m.Groups['msg'].Value.Trim()
        $component = $m.Groups['component'].Value
        $typeVal   = $m.Groups['type'].Value

        $timestamp = $null
        try {
            $dateParts = $rawDate -split '-'
            $timePart  = $rawTime -replace '[+\-]\d+$', ''
            $timeParts = $timePart -split '[:.]'

            $timestamp = [datetime]::new(
                [int]$dateParts[2], [int]$dateParts[0], [int]$dateParts[1],
                [int]$timeParts[0], [int]$timeParts[1], [int]$timeParts[2]
            )

            if ($timeParts.Count -ge 4 -and $timeParts[3]) {
                $frac  = $timeParts[3].PadRight(7, '0').Substring(0, 7)
                $timestamp = $timestamp.AddTicks([long]$frac)
            }
        }
        catch {
            # Leave timestamp null on parse failure.
        }

        # Advance the newline pointer to the first newline at-or-after this match.
        while ($nlPtr -lt $nlCount -and $newlinePositions[$nlPtr] -lt $m.Index) {
            $nlPtr++
        }
        $lineNumber = $nlPtr + 1

        $severity = if ($script:CMTraceSeverityMap.ContainsKey($typeVal)) {
            $script:CMTraceSeverityMap[$typeVal]
        } else { 'Unknown' }

        $results.Add([PSCustomObject]@{
            Timestamp  = $timestamp
            Message    = $message
            Severity   = $severity
            Component  = $component
            Source     = $fileName
            FullPath   = $Path
            LineNumber = $lineNumber
        })
    }

    return $results
}
