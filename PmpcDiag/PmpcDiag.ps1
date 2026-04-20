#Requires -Version 5.1

<#
.SYNOPSIS
    PmpcDiag - Patch My PC Intune Log Troubleshooter
.DESCRIPTION
    WPF desktop tool that parses Patch My PC and Intune Management Extension logs,
    searches by keyword, and displays results in a sortable grid with detail view.
.NOTES
    Run this script directly: .\PmpcDiag.ps1
    Requires PowerShell 5.1+ on Windows.
#>

# --- Load assemblies ---
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# --- Dot-source library functions ---
$scriptRoot = $PSScriptRoot
. "$scriptRoot\Lib\Read-CMTraceLog.ps1"
. "$scriptRoot\Lib\Get-LogPaths.ps1"
. "$scriptRoot\Lib\Search-Logs.ps1"
. "$scriptRoot\Lib\DefaultKeywords.ps1"

# --- Load XAML ---
$xamlPath = Join-Path $scriptRoot 'UI\MainWindow.xaml'
$xamlContent = Get-Content -Path $xamlPath -Raw

# Convert x:Name to Name for PowerShell compatibility (keep xmlns:x for x:Key)
$xamlContent = $xamlContent -replace 'x:Name=', 'Name='

$xamlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
$window = [System.Windows.Markup.XamlReader]::Load($xamlReader)

# --- Find all named controls ---
$txtKeywords  = $window.FindName('txtKeywords')
$chkDefaults  = $window.FindName('chkDefaults')
$rbAll        = $window.FindName('rbAll')
$rbPatchMyPC  = $window.FindName('rbPatchMyPC')
$rbIME        = $window.FindName('rbIME')
$chkError     = $window.FindName('chkError')
$chkWarning   = $window.FindName('chkWarning')
$chkInfo      = $window.FindName('chkInfo')
$dpAfter      = $window.FindName('dpAfter')
$dpBefore     = $window.FindName('dpBefore')
$btnSearch    = $window.FindName('btnSearch')
$btnExport    = $window.FindName('btnExport')
$txtLogPath   = $window.FindName('txtLogPath')
$btnBrowse    = $window.FindName('btnBrowse')
$dgResults    = $window.FindName('dgResults')
$txtDetail    = $window.FindName('txtDetail')
$tbStatus     = $window.FindName('tbStatus')
$tbStatusRight = $window.FindName('tbStatusRight')

# Store current results for export
$script:currentResults = @()
$script:allParsedEntries = @()

# --- Helper: get selected LogSet ---
function Get-SelectedLogSet {
    if ($rbPatchMyPC.IsChecked) { return 'PatchMyPC' }
    if ($rbIME.IsChecked) { return 'IME' }
    return 'All'
}

# --- Helper: get selected severities ---
function Get-SelectedSeverities {
    $sevs = @()
    if ($chkError.IsChecked)   { $sevs += 'Error' }
    if ($chkWarning.IsChecked) { $sevs += 'Warning' }
    if ($chkInfo.IsChecked)    { $sevs += 'Info' }
    return $sevs
}

# --- Helper: build keyword list ---
function Get-KeywordList {
    $keywords = @()

    # User-supplied keywords (comma-separated)
    $userInput = $txtKeywords.Text.Trim()
    if ($userInput) {
        $keywords += $userInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    # Default keywords
    if ($chkDefaults.IsChecked) {
        $keywords += $script:DefaultKeywords
    }

    # Deduplicate (case-insensitive)
    $keywords | Select-Object -Unique
}

# --- Browse button handler ---
$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select log directory'
    $dialog.ShowNewFolderButton = $false

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtLogPath.Text = $dialog.SelectedPath
    }
})

# --- Search button handler ---
$btnSearch.Add_Click({
    $tbStatus.Text = 'Searching...'
    $tbStatusRight.Text = ''
    $txtDetail.Text = ''
    $dgResults.ItemsSource = $null
    $script:currentResults = @()

    # Force UI update
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [action]{}
    )

    try {
        # Determine log set
        $logSet = Get-SelectedLogSet

        # Get log files
        $customPath = $txtLogPath.Text.Trim()
        if ($customPath -and (Test-Path -LiteralPath $customPath)) {
            # Custom path: find all .log files in the directory
            $logFiles = Get-ChildItem -Path $customPath -Filter '*.log' -File -ErrorAction SilentlyContinue
            if (-not $logFiles) {
                $tbStatus.Text = "No .log files found in: $customPath"
                return
            }
        }
        else {
            $logFiles = Get-LogPaths -LogSet $logSet
            if (-not $logFiles -or $logFiles.Count -eq 0) {
                $tbStatus.Text = 'No log files found. Check that PMPC/IME logs exist on this machine, or use the Browse button to point to a log directory.'
                return
            }
        }

        # Parse all log files
        $allEntries = @()
        $filesProcessed = 0
        $parseWarnings = @()

        foreach ($logFile in $logFiles) {
            try {
                $entries = @(Read-CMTraceLog -Path $logFile.FullName)
                $allEntries += $entries
                $filesProcessed++
            }
            catch {
                $parseWarnings += "Failed to parse $($logFile.Name): $($_.Exception.Message)"
            }
        }

        $script:allParsedEntries = $allEntries
        $totalEntries = $allEntries.Count

        if ($totalEntries -eq 0) {
            $tbStatus.Text = "Parsed $filesProcessed file(s) but found 0 log entries. Files may not be CMTrace format."
            return
        }

        # Get keywords
        $keywords = @(Get-KeywordList)
        if ($keywords.Count -eq 0) {
            # No keywords — show all entries filtered by severity/date only
            $keywords = $null
        }

        # Get severity filter
        $severities = @(Get-SelectedSeverities)
        if ($severities.Count -eq 0) {
            $tbStatus.Text = 'Select at least one severity level.'
            return
        }

        # Get date filters
        $after  = $dpAfter.SelectedDate
        $before = $dpBefore.SelectedDate

        # Search
        $searchParams = @{
            LogEntries = $allEntries
            Severities = $severities
        }
        if ($keywords)  { $searchParams['Keywords'] = $keywords }
        if ($after)     { $searchParams['After'] = $after }
        if ($before)    { $searchParams['Before'] = $before }

        $results = @(Search-Logs @searchParams)
        $script:currentResults = $results

        # Bind to DataGrid
        $dgResults.ItemsSource = $results

        # Update status
        $matchCount = $results.Count
        $fileCount  = ($results | Select-Object -ExpandProperty Source -Unique).Count
        $tbStatus.Text = "Found $matchCount matches across $fileCount file(s)"
        $tbStatusRight.Text = "$totalEntries total entries from $filesProcessed file(s)"

        if ($parseWarnings.Count -gt 0) {
            $tbStatus.Text += " | Warnings: $($parseWarnings.Count)"
        }
    }
    catch {
        $tbStatus.Text = "Error: $($_.Exception.Message)"
    }
})

# --- DataGrid selection changed → update detail panel ---
$dgResults.Add_SelectionChanged({
    $selected = $dgResults.SelectedItem
    if ($selected) {
        $detail = @(
            "Timestamp:  $($selected.Timestamp)"
            "Source:     $($selected.Source)"
            "Severity:   $($selected.Severity)"
            "Component:  $($selected.Component)"
            "Line:       $($selected.LineNumber)"
            "Full Path:  $($selected.FullPath)"
            ""
            "--- Message ---"
            $selected.Message
        ) -join "`r`n"

        $txtDetail.Text = $detail
    }
    else {
        $txtDetail.Text = ''
    }
})

# --- Export CSV button handler ---
$btnExport.Add_Click({
    if (-not $script:currentResults -or $script:currentResults.Count -eq 0) {
        $tbStatus.Text = 'No results to export. Run a search first.'
        return
    }

    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*'
    $saveDialog.DefaultExt = 'csv'
    $saveDialog.FileName = "PmpcDiag_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $script:currentResults |
                Select-Object Timestamp, Source, Severity, Component, LineNumber, Message, FullPath |
                Export-Csv -Path $saveDialog.FileName -NoTypeInformation -Encoding UTF8

            $tbStatus.Text = "Exported $($script:currentResults.Count) results to $($saveDialog.FileName)"
        }
        catch {
            $tbStatus.Text = "Export failed: $($_.Exception.Message)"
        }
    }
})

# --- Allow Enter key in keywords to trigger search ---
$txtKeywords.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) {
        $btnSearch.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    }
})

# --- Show the window ---
$window.ShowDialog() | Out-Null
