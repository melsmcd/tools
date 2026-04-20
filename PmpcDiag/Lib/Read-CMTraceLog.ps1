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
    $content  = Get-Content -Path $Path -Raw -ErrorAction Stop

    # CMTrace format (SingleLine so '.' matches newlines for multiline messages):
    # <![LOG[message]LOG]!><time="HH:mm:ss.fffffff+offset" date="M-DD-YYYY" component="..." context="" type="N" thread="N" file="">
    $pattern = '<!\[LOG\[(?<msg>.*?)\]LOG\]!>.*?time="(?<time>[\d:.+\-]+).*?".*?date="(?<date>[\d-]+)".*?component="(?<component>[^"]*)".*?type="(?<type>\d)"'

    $matches = [regex]::Matches(
        $content,
        $pattern,
        [System.Text.RegularExpressions.RegexOptions]::SingleLine
    )

    $severityMap = @{ '1' = 'Info'; '2' = 'Warning'; '3' = 'Error' }

    foreach ($m in $matches) {
        $rawTime = $m.Groups['time'].Value
        $rawDate = $m.Groups['date'].Value
        $message = $m.Groups['msg'].Value.Trim()
        $component = $m.Groups['component'].Value
        $typeVal  = $m.Groups['type'].Value

        # Parse timestamp by extracting components directly
        # Date: "M-DD-YYYY" or "MM-DD-YYYY"  Time: "HH:mm:ss.fffffff" optionally "+offset"
        $timestamp = $null
        try {
            $dateParts = $rawDate -split '-'
            $timePart  = $rawTime -replace '[+\-]\d+$', ''
            $timeParts = $timePart -split '[:.]'

            $month  = [int]$dateParts[0]
            $day    = [int]$dateParts[1]
            $year   = [int]$dateParts[2]
            $hour   = [int]$timeParts[0]
            $minute = [int]$timeParts[1]
            $second = [int]$timeParts[2]

            $timestamp = [datetime]::new($year, $month, $day, $hour, $minute, $second)

            # Add fractional seconds if present
            if ($timeParts.Count -ge 4 -and $timeParts[3]) {
                $frac = $timeParts[3].PadRight(7, '0').Substring(0, 7)
                $ticks = [long]$frac
                $timestamp = $timestamp.AddTicks($ticks)
            }
        }
        catch {
            # Timestamp parse failed — leave as null
        }

        # Calculate line number from position in the file
        $lineNumber = ($content.Substring(0, $m.Index) -split "`n").Count

        $severity = if ($severityMap.ContainsKey($typeVal)) { $severityMap[$typeVal] } else { 'Unknown' }

        [PSCustomObject]@{
            Timestamp  = $timestamp
            Message    = $message
            Severity   = $severity
            Component  = $component
            Source     = $fileName
            FullPath   = $Path
            LineNumber = $lineNumber
        }
    }
}
