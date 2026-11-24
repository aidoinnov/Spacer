#requires -Version 5.1
<# Windows-only. Prepared on macOS; NOT executed there.
   Syntax source: shipped 2.2.0.27 User Manual section 11, pp26-28.
   Timeout Kill is harness cleanup, never evidence of application cancellation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$MacSnapshot,
    [ValidateRange(10,3600)][int]$TimeoutSeconds = 120,
    [ValidateRange(1,10000)][int]$FixtureFiles = 256,
    [switch]$HelpOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ExpectedHash = '192176a0ff46d84d27885e9d38e60157bc692eaf5d1e5b75ca56b3beaa0de7a6'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required. No execution has been performed.' }
$Executable = (Resolve-Path -LiteralPath $Executable).ProviderPath
if ((Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedHash) { throw 'Frozen executable SHA256 mismatch.' }
# Do not interfere with an existing UI session, including possible single-instance forwarding.
if (@(Get-Process -Name SpaceSniffer -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Close existing SpaceSniffer sessions before this isolated QA run.' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw 'OutputDirectory must be a NEW directory. Existing results are never overwritten.' }
if ($OutputDirectory.IndexOfAny([char[]]@(';','"')) -ge 0) { throw 'OutputDirectory must not contain semicolon or quote (CLI path-list delimiters).' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$Bin = New-Item -ItemType Directory -Path (Join-Path $OutputDirectory 'bin')
$RunExe = Join-Path $Bin.FullName 'SpaceSniffer.exe'
Copy-Item -LiteralPath $Executable -Destination $RunExe
$Utf8 = New-Object Text.UTF8Encoding($false)
function Write-Json($Path, $Value) { [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 12), $Utf8) }
# Shipped EXE help: INTERNAL parser is default; quote delimiters, NO escape char.
# Backslashes remain literal, including the final separator. Avoid OS CRT quoting.
function Quote-Argument([string]$Value) {
    if ($Value.IndexOf('"') -ge 0 -or $Value.IndexOf("`r") -ge 0 -or $Value.IndexOf("`n") -ge 0) { throw 'Unsupported internal-parser delimiter in argument.' }
    return '"' + $Value + '"'
}
$QuoteVectors = @(
    @{ Input=''; Expected='""' },
    @{ Input='C:\with space\'; Expected='"C:\with space\"' }
)
foreach ($Vector in $QuoteVectors) { if ((Quote-Argument $Vector.Input) -cne $Vector.Expected) { throw 'Argument quoting self-check failed.' } }
$Version = [Diagnostics.FileVersionInfo]::GetVersionInfo($RunExe)
$Identity = [ordered]@{
    prepared_status='PREPARED_NOT_EXECUTED_ON_MACOS'; runtime_started_utc=[DateTime]::UtcNow.ToString('o')
    source_executable=$Executable; staged_executable=$RunExe; sha256=$ExpectedHash
    file_version=$Version.FileVersion; product_version=$Version.ProductVersion
    os=[Environment]::OSVersion.VersionString; is_64bit_os=[Environment]::Is64BitOperatingSystem
    powershell=$PSVersionTable.PSVersion.ToString(); user=[Environment]::UserName
    timeout_seconds=$TimeoutSeconds; sample_interval_ms=200
    syntax_source='Frozen EXE embedded help + shipped User Manual section 11 pp26-28; internal parser default, literal quote delimiters, no escaping; help, NOT --help'
    controls='No native cancel CLI is proven. Timeout Kill affects only this harness-owned process and is not native cancellation.'
}
Write-Json (Join-Path $OutputDirectory 'identity.json') $Identity
$Results = New-Object 'Collections.Generic.List[object]'
function Invoke-Case([string]$Name, [string[]]$Arguments, [string[]]$ExpectedArtifacts) {
    $CaseDir = New-Item -ItemType Directory -Path (Join-Path $OutputDirectory $Name)
    $Quoted = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
    Write-Json (Join-Path $CaseDir.FullName 'command.json') @{ executable=$RunExe; argv=$Arguments; windows_command_line=$Quoted; expected_artifacts=$ExpectedArtifacts }
    $Info = New-Object Diagnostics.ProcessStartInfo
    $Info.FileName=$RunExe; $Info.Arguments=$Quoted; $Info.WorkingDirectory=$Bin.FullName
    $Info.UseShellExecute=$false; $Info.RedirectStandardOutput=$true; $Info.RedirectStandardError=$true
    $Process = New-Object Diagnostics.Process; $Process.StartInfo=$Info
    $Samples = New-Object IO.StreamWriter((Join-Path $CaseDir.FullName 'resources.jsonl'), $false, $Utf8)
    $Clock=[Diagnostics.Stopwatch]::StartNew(); $TimedOut=$false; $CleanupKilled=$false; $Started=$false
    $ExitCode=$null; $RunError=$null; $OutTask=$null; $ErrTask=$null; $OwnedPid=$null
    try {
        $Started=$Process.Start(); if (-not $Started) { throw 'Process.Start returned false' }
        $OwnedPid=$Process.Id; $OutTask=$Process.StandardOutput.ReadToEndAsync(); $ErrTask=$Process.StandardError.ReadToEndAsync()
        while (-not $Process.WaitForExit(200)) {
            try {
                $Process.Refresh()
                $Sample=@{ elapsed_ms=$Clock.ElapsedMilliseconds; pid=$OwnedPid; cpu_ms=$Process.TotalProcessorTime.TotalMilliseconds
                    working_set_bytes=$Process.WorkingSet64; peak_working_set_bytes=$Process.PeakWorkingSet64
                    private_bytes=$Process.PrivateMemorySize64; virtual_bytes=$Process.VirtualMemorySize64
                    handles=$Process.HandleCount; threads=$Process.Threads.Count }
                $Samples.WriteLine((ConvertTo-Json -Compress -InputObject $Sample)); $Samples.Flush()
            } catch { $Samples.WriteLine((ConvertTo-Json -Compress -InputObject @{ elapsed_ms=$Clock.ElapsedMilliseconds; sample_error=$_.Exception.Message })) }
            if ($Clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $TimedOut=$true; $Process.Kill(); $CleanupKilled=$true; $Process.WaitForExit(); break
            }
        }
        $Process.WaitForExit(); $ExitCode=$Process.ExitCode
    } catch { $RunError=$_.Exception.Message }
    finally {
        # Even a harness exception must not leave its own child running.
        if ($Started) { try { if (-not $Process.HasExited) { $Process.Kill(); $CleanupKilled=$true; $Process.WaitForExit() } } catch {} }
        $Clock.Stop(); $Samples.Dispose()
        if ($null -ne $OutTask) { [IO.File]::WriteAllText((Join-Path $CaseDir.FullName 'stdout.txt'), $OutTask.GetAwaiter().GetResult(), $Utf8) }
        if ($null -ne $ErrTask) { [IO.File]::WriteAllText((Join-Path $CaseDir.FullName 'stderr.txt'), $ErrTask.GetAwaiter().GetResult(), $Utf8) }
        $Process.Dispose()
    }
    $Artifacts=@(foreach ($Path in $ExpectedArtifacts) {
        $Exists=Test-Path -LiteralPath $Path -PathType Leaf
        if ($Exists) { $Item=Get-Item -LiteralPath $Path; @{ path=$Path; exists=$true; bytes=$Item.Length; sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } }
        else { @{ path=$Path; exists=$false } }
    })
    $Record=@{ name=$Name; pid=$OwnedPid; exit_code=$ExitCode; elapsed_ms=$Clock.ElapsedMilliseconds; timeout=$TimedOut
        cleanup_killed=$CleanupKilled; harness_error=$RunError; artifacts=$Artifacts
        observation_only=$true; semantic_equivalence='NOT_AUTOMATICALLY_ASSERTED'; missing_artifacts=@($Artifacts | Where-Object { -not $_.exists }).Count }
    Write-Json (Join-Path $CaseDir.FullName 'result.json') $Record
    $Results.Add($Record); Write-Json (Join-Path $OutputDirectory 'results.json') @($Results.ToArray())
    return $Record
}
if ($HelpOnly) {
    # Proven help is interactive. Operator must dismiss/close the QA UI.
    Invoke-Case '00-help-manual-close' @('help') @() | Out-Null
} else {
    $Fixture = New-Item -ItemType Directory -Path (Join-Path $OutputDirectory 'Fixture With Spaces')
    foreach ($Name in @('branch-A','branch-B','empty')) { New-Item -ItemType Directory -Path (Join-Path $Fixture.FullName $Name) | Out-Null }
    for ($Index=0; $Index -lt $FixtureFiles; $Index++) {
        $Branch=if ($Index % 2 -eq 0) { 'branch-A' } else { 'branch-B' }
        $Path=Join-Path (Join-Path $Fixture.FullName $Branch) ('file-{0:D5}.bin' -f $Index)
        [IO.File]::WriteAllBytes($Path, (New-Object byte[] (($Index % 5) * 513)))
    }
    $UnicodeName=([string][char]0xD55C)+([string][char]0xAE00)+'-'+[char]::ConvertFromUtf32(0x1F600)+'.txt'
    [IO.File]::WriteAllText((Join-Path $Fixture.FullName $UnicodeName),'fixture',$Utf8)
    $Hidden=Join-Path $Fixture.FullName 'hidden-readonly.bin'; [IO.File]::WriteAllBytes($Hidden,[byte[]](1,2,3))
    [IO.File]::SetAttributes($Hidden, [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::ReadOnly)
    Write-Json (Join-Path $OutputDirectory 'fixture.json') @{ root=$Fixture.FullName; generated_regular_files=($FixtureFiles+2); generated_child_folders=3; scope='small owned fixture, no hardlink/sparse/ACL assumptions'; files=@(Get-ChildItem -LiteralPath $Fixture.FullName -File -Recurse -Force | ForEach-Object { @{ path=$_.FullName; bytes=$_.Length; attributes=$_.Attributes.ToString(); sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } }) }
    $Saved=Join-Path $OutputDirectory 'native-generated.sns'
    $First=Invoke-Case '01-scan-save-autoclose' @('scan',$Fixture.FullName,'save',$Saved,'autoclose') @($Saved)
    if ((Test-Path -LiteralPath $Saved) -and -not $First.cleanup_killed) {
        $Resaved=Join-Path $OutputDirectory 'native-resaved.sns'
        Invoke-Case '02-native-load-resave' @('load',$Saved,'save',$Resaved,'autoclose') @($Resaved) | Out-Null
        $Export=Join-Path $OutputDirectory 'native-loaded.txt'
        Invoke-Case '03-native-load-export' @('load',$Saved,'export','Grouped by folder',$Export,'autoclose') @($Export) | Out-Null
    }
    foreach ($Variant in @(@{ name='04-path-trailing'; path=($Fixture.FullName.TrimEnd('\')+'\') }, @{ name='05-path-uppercase'; path=$Fixture.FullName.ToUpperInvariant() })) {
        $Target=Join-Path $OutputDirectory ($Variant.name+'.sns')
        Invoke-Case $Variant.name @('scan',$Variant.path,'save',$Target,'autoclose') @($Target) | Out-Null
    }
    # Same-process duplicate requests are documented to share cache; artifacts alone do not prove the hit.
    $CacheA=Join-Path $OutputDirectory 'cache-view-a.sns'; $CacheB=Join-Path $OutputDirectory 'cache-view-b.sns'
    Invoke-Case '06-duplicate-path-two-views' @('scan',$Fixture.FullName,'save',$CacheA,'scan',$Fixture.FullName,'save',$CacheB,'autoclose') @($CacheA,$CacheB) | Out-Null
    $VariantA=Join-Path $OutputDirectory 'variant-base.sns'; $VariantB=Join-Path $OutputDirectory 'variant-trailing.sns'; $VariantC=Join-Path $OutputDirectory 'variant-uppercase.sns'
    Invoke-Case '06b-path-variants-one-process' @('scan',$Fixture.FullName,'save',$VariantA,'scan',($Fixture.FullName.TrimEnd('\')+'\'),'save',$VariantB,'scan',$Fixture.FullName.ToUpperInvariant(),'save',$VariantC,'autoclose') @($VariantA,$VariantB,$VariantC) | Out-Null
    $Restart=Join-Path $OutputDirectory 'fresh-process.sns'
    Invoke-Case '07-fresh-process-explicit-rescan' @('scan',$Fixture.FullName,'save',$Restart,'autoclose') @($Restart) | Out-Null
    if ($MacSnapshot) {
        $MacInputPath=(Resolve-Path -LiteralPath $MacSnapshot).ProviderPath
        $Copied=Join-Path $OutputDirectory 'mac-input.sns'; Copy-Item -LiteralPath $MacInputPath -Destination $Copied
        Write-Json (Join-Path $OutputDirectory 'mac-input.json') @{ source=$MacInputPath; copy=$Copied; bytes=(Get-Item -LiteralPath $Copied).Length; sha256=(Get-FileHash -LiteralPath $Copied -Algorithm SHA256).Hash.ToLowerInvariant() }
        $Roundtrip=Join-Path $OutputDirectory 'mac-input-native-resaved.sns'
        Invoke-Case '08-mac-load-native-resave' @('load',$Copied,'save',$Roundtrip,'autoclose') @($Roundtrip) | Out-Null
        $MacExport=Join-Path $OutputDirectory 'mac-input-native.txt'
        Invoke-Case '09-mac-load-native-export' @('load',$Copied,'export','Grouped by folder',$MacExport,'autoclose') @($MacExport) | Out-Null
    }
}
Write-Json (Join-Path $OutputDirectory 'manual-required.json') @{
    status='MANUAL_WINDOWS_OBSERVATION_REQUIRED'
    cancellation='No stop/cancel CLI proven. In an owned QA window, manually Stop scan/export; record event time and observe remaining export abort/autoclose ignored. Kill on timeout is not this test.'
    cache='Use one process with multiple views; observe case/trailing path reuse with profiler/log evidence. Matching SNS or short time alone does not prove a cache hit.'
    restart='Explicit scan after restart does not establish automatic persistent-cache presence/absence. Separately launch with no arguments and record UI/storage reads before any scan/load.'
    roundtrip='Bring native-generated/resaved SNS plus hashes to Mac; compare parsed tree/fields with path/platform/cluster policies explicit. Native resave byte inequality alone is not failure.'
    help='Run -HelpOnly into a separate NEW output directory; capture help dialog screenshot/text and close its QA process manually.'
}
$AllArtifacts=@(Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse -Force | Where-Object { $_.Name -ne 'manifest.json' } | ForEach-Object { @{ path=$_.FullName.Substring($OutputDirectory.Length+1); bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } })
Write-Json (Join-Path $OutputDirectory 'manifest.json') @{ created_utc=[DateTime]::UtcNow.ToString('o'); files=$AllArtifacts; runtime_cases=$Results.Count; not_a_pass_certificate=$true }
Write-Output ('Observations retained at '+$OutputDirectory+'; inspect results.json and manual-required.json. No equivalence completion is implied.')

if (@($Results.ToArray() | Where-Object { $_.timeout -or $_.cleanup_killed -or $_.harness_error -or $_.missing_artifacts -gt 0 -or $_.exit_code -ne 0 }).Count -gt 0) { exit 2 }
