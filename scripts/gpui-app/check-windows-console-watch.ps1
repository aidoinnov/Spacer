<# Run in an interactive user session. Reads window/process metadata only: no input or activation.
   A hidden QA-feature binary is required. Stops only its own process tree if a guard fails. #>
param(
 [Parameter(Mandatory=$true)][string]$PythonExe,
 [Parameter(Mandatory=$true)][string]$QABinary,
 [Parameter(Mandatory=$true)][string]$Backend,
 [Parameter(Mandatory=$true)][string]$HarnessDirectory,
 [Parameter(Mandatory=$true)][string]$Output,
 [ValidateRange(30,86400)][int]$Seconds=900,
 [ValidateRange(1,1024)][int]$MaximumRssGrowthMB=64
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$QABinary=[IO.Path]::GetFullPath($QABinary);$Backend=[IO.Path]::GetFullPath($Backend)
if(Test-Path -LiteralPath $Output){throw 'Use a fresh output'}
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class OwnedConsoleWatch {
 delegate bool Callback(IntPtr window,IntPtr data);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback callback,IntPtr data);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder text,int capacity);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window,StringBuilder text,int capacity);
 public static int Count(string backend) {
  int count=0;
  EnumWindows((window,data)=>{
   if(!IsWindowVisible(window))return true;
   var type=new StringBuilder(256);GetClassName(window,type,type.Capacity);
   if(type.ToString()!="ConsoleWindowClass")return true;
   var title=new StringBuilder(4096);GetWindowText(window,title,title.Capacity);
   if(title.ToString().IndexOf(backend,StringComparison.OrdinalIgnoreCase)>=0)count++;
   return true;
  },IntPtr.Zero);
  return count;
 }
}
'@
$env:SNIFFER_SCAN_BACKEND=$Backend
Set-Location -LiteralPath $HarnessDirectory
# Paths are passed as argv, never interpolated into Python or shell code.
$bootstrap="import sys,runpy;sys.path.insert(0,'.');sys.argv=['check-watch-soak.py',sys.argv[1],'--background-qa','--seconds',sys.argv[2],'--output',sys.argv[3]];runpy.run_path('check-watch-soak.py',run_name='__main__')"
$arguments=@('-c',('"'+$bootstrap+'"'),('"'+$QABinary+'"'),$Seconds.ToString(),('"'+$Output+'"'))
$python=Start-Process -FilePath $PythonExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($Output+'.runner.log') -RedirectStandardError ($Output+'.runner.err')
# Cache the handle while the process is alive; otherwise PowerShell/.NET may
# return a null ExitCode when first opening it after the process has disappeared.
$processHandle=$python.Handle
$ownedGui=@();$allOwnedGui=@();$samples=@();$started=[DateTime]::UtcNow;$failure=$null
$baselineRss=0L;$postWarmupPeak=0L
try {
 while(!$python.HasExited){
  $gui=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($python.Id)"|Where-Object {$_.ExecutablePath -eq $QABinary})
  $ownedGui=@($gui|ForEach-Object {[int]$_.ProcessId})
  $allOwnedGui=@(@($allOwnedGui+$ownedGui)|Select-Object -Unique)
  $children=@();foreach($id in $ownedGui){$children+=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$id"|Where-Object {$_.ExecutablePath -eq $Backend})}
  $visible=[OwnedConsoleWatch]::Count($Backend)
  $rss=0L;foreach($id in $ownedGui){$process=Get-Process -Id $id -ErrorAction SilentlyContinue;if($process){$rss+=$process.WorkingSet64}}
  $elapsed=([DateTime]::UtcNow-$started).TotalSeconds
  if($elapsed -ge 60 -and $rss -gt 0){if($baselineRss -eq 0){$baselineRss=$rss};$postWarmupPeak=[Math]::Max($postWarmupPeak,$rss)}
  $sample=@{seconds=$elapsed;guiPids=$ownedGui;nativePids=@($children|ForEach-Object {[int]$_.ProcessId});visibleBackendConsoles=$visible;guiRssBytes=$rss}
  $samples+=$sample
  ($sample|ConvertTo-Json -Compress -Depth 5)|Add-Content -Encoding UTF8 -LiteralPath ($Output+'.processes.jsonl')
  if($visible -gt 0){throw 'A backend console became visible'}
  if($children.Count -gt 4){throw 'Native backend count exceeded the bounded scan/document leases'}
  if($baselineRss -gt 0 -and $rss-$baselineRss -gt $MaximumRssGrowthMB*1MB){throw 'Tiny-fixture capture RSS exceeded its post-warmup growth budget'}
  if(([DateTime]::UtcNow-$started).TotalSeconds -gt $Seconds+90){throw 'Owned soak exceeded deadline'}
  Start-Sleep -Milliseconds 500;$python.Refresh()
 }
 $python.WaitForExit()
 if($null -eq $python.ExitCode -or $python.ExitCode -ne 0){throw ('Owned soak exit status unavailable or nonzero: '+$python.ExitCode)}
 $result=Get-Content -LiteralPath $Output -Raw|ConvertFrom-Json
 if(!$result.passed){throw 'Owned soak did not pass'}
}catch{$failure=$_.ToString()}
finally {
 $last=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($python.Id)"|Where-Object {$_.ExecutablePath -eq $QABinary}|ForEach-Object {[int]$_.ProcessId})
 $allOwnedGui=@(@($allOwnedGui+$last)|Select-Object -Unique)
 foreach($id in $allOwnedGui){
  $owned=Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
  if($owned -and $owned.ExecutablePath -eq $QABinary -and $owned.ParentProcessId -eq $python.Id){Stop-Process -Id $id -ErrorAction SilentlyContinue}
 }
 if(!$python.HasExited){Stop-Process -Id $python.Id -ErrorAction SilentlyContinue}
 Start-Sleep -Seconds 2
 $live=@();foreach($id in $allOwnedGui){$live+=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$id"|Where-Object {$_.ExecutablePath -eq $Backend})}
 $report=@{passed=(!$failure -and $live.Count -eq 0);error=$failure;noMouseKeyboardInput=$true;noAppActivation=$true;samples=$samples.Count;nativePeak=($samples|ForEach-Object {$_.nativePids.Count}|Measure-Object -Maximum).Maximum;visibleConsolePeak=($samples|ForEach-Object {$_.visibleBackendConsoles}|Measure-Object -Maximum).Maximum;nativeChildrenAfterClose=$live.Count;rssWarmupSeconds=60;rssBaselineBytes=$baselineRss;rssPostWarmupPeakBytes=$postWarmupPeak;rssGrowthBudgetBytes=$MaximumRssGrowthMB*1MB;qaSHA256=(Get-FileHash $QABinary).Hash.ToLower()}
 $report|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 -LiteralPath ($Output+'.guard.json')
}
if($failure){throw $failure}
