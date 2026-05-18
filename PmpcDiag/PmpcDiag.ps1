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
$tcResults    = $window.FindName('tcResults')
$txtDetail    = $window.FindName('txtDetail')
$tbStatus     = $window.FindName('tbStatus')
$tbStatusRight = $window.FindName('tbStatusRight')

# --- DataGrid XAML template (one instance created per results tab) ---
$script:dataGridTemplate = @'
<DataGrid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
          AutoGenerateColumns="False" IsReadOnly="True"
          SelectionMode="Single" SelectionUnit="FullRow"
          Background="#1E1E2E"
          Foreground="#CDD6F4"
          RowBackground="#1E1E2E" AlternatingRowBackground="#252538"
          BorderBrush="#45475A" BorderThickness="0"
          GridLinesVisibility="Horizontal"
          HorizontalGridLinesBrush="#313244"
          HeadersVisibility="Column"
          FontSize="12.5"
          CanUserSortColumns="True"
          CanUserReorderColumns="True"
          CanUserResizeColumns="True">
    <DataGrid.ColumnHeaderStyle>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
        </Style>
    </DataGrid.ColumnHeaderStyle>
    <DataGrid.CellStyle>
        <Style TargetType="DataGridCell">
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#45475A"/>
                    <Setter Property="Foreground" Value="#CDD6F4"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </DataGrid.CellStyle>
    <DataGrid.Columns>
        <DataGridTextColumn Header="Timestamp" Binding="{Binding Timestamp, StringFormat='{}{0:yyyy-MM-dd HH:mm:ss.fff}'}" Width="175"/>
        <DataGridTextColumn Header="Source" Binding="{Binding Source}" Width="180"/>
        <DataGridTextColumn Header="Severity" Binding="{Binding Severity}" Width="80"/>
        <DataGridTextColumn Header="Component" Binding="{Binding Component}" Width="150"/>
        <DataGridTextColumn Header="Line" Binding="{Binding LineNumber}" Width="55"/>
        <DataGridTextColumn Header="Message" Binding="{Binding Message}" Width="*"/>
    </DataGrid.Columns>
</DataGrid>
'@

function New-ResultsDataGrid {
    param([object[]]$Items)

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($script:dataGridTemplate))
    $dg = [System.Windows.Markup.XamlReader]::Load($reader)
    $dg.ItemsSource = $Items

    $dg.Add_SelectionChanged({
        param($sender, $e)
        $selected = $sender.SelectedItem
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
    })

    return $dg
}

function Add-ResultsTab {
    param(
        [string]$Header,
        [object[]]$Items
    )
    $tab = New-Object System.Windows.Controls.TabItem
    $tab.Header = $Header
    $tab.Content = New-ResultsDataGrid -Items $Items
    $tcResults.Items.Add($tab) | Out-Null
}

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
    $tcResults.Items.Clear()
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

        # Parse all log files (List avoids O(n^2) array re-allocation on +=).
        $allEntries     = [System.Collections.Generic.List[psobject]]::new()
        $filesProcessed = 0
        $parseWarnings  = [System.Collections.Generic.List[string]]::new()

        foreach ($logFile in $logFiles) {
            try {
                $entries = Read-CMTraceLog -Path $logFile.FullName
                if ($entries) {
                    $allEntries.AddRange([psobject[]]@($entries))
                }
                $filesProcessed++
            }
            catch {
                $parseWarnings.Add("Failed to parse $($logFile.Name): $($_.Exception.Message)")
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

        # Build tabs: "All Results" plus one tab per source file that has hits
        Add-ResultsTab -Header "All Results ($($results.Count))" -Items $results

        $groups = $results | Group-Object -Property Source | Sort-Object Name
        foreach ($g in $groups) {
            Add-ResultsTab -Header "$($g.Name) ($($g.Count))" -Items @($g.Group)
        }

        if ($tcResults.Items.Count -gt 0) {
            $tcResults.SelectedIndex = 0
        }

        # Update status
        $matchCount = $results.Count
        $fileCount  = $groups.Count
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
