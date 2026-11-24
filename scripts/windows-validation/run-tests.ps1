param([Parameter(Mandatory=$true)][string]$Workspace)
$ProgressPreference='SilentlyContinue'
$ErrorActionPreference='Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding
$OutputEncoding = [Console]::OutputEncoding
$root=(Resolve-Path -LiteralPath $Workspace).Path
$env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')+';'+$env:Path
foreach($key in @('SDKROOT','DEVELOPER_DIR')){$v=[Environment]::GetEnvironmentVariable($key,'Machine');if(!$v){$v=[Environment]::GetEnvironmentVariable($key,'User')};if($v){Set-Item ('env:'+$key) $v}}
$swift=Get-Command swift -ErrorAction SilentlyContinue
if(!$swift){$swift=Get-ChildItem 'C:\Library\Developer\Toolchains',(Join-Path $env:LOCALAPPDATA 'Programs\Swift\Toolchains') -Filter swift.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1;if($swift){$env:Path=$swift.DirectoryName+';'+$env:Path}}
$expected=Get-Content (Join-Path $root 'source-manifest.json') -Raw | ConvertFrom-Json
$zip=Join-Path $root 'engine.zip'
if((Get-FileHash $zip -Algorithm SHA256).Hash -ne $expected.zip_sha256){throw 'Source ZIP hash mismatch'}
$pkg=Join-Path $root 'engine';if(Test-Path $pkg){throw 'Refusing existing source directory'}
Expand-Archive -LiteralPath $zip -DestinationPath $root
foreach($item in $expected.sources.PSObject.Properties){$file=Join-Path $pkg $item.Name;if((Get-FileHash $file -Algorithm SHA256).Hash -ne $item.Value){throw ('Source hash mismatch '+$item.Name)}}
Push-Location $pkg
try{
 & swift --version 2>&1 | Out-File (Join-Path $root 'swift-version.log') -Encoding utf8
 if($LASTEXITCODE -ne 0){throw 'Swift unavailable'}
 $report=@{host=$env:COMPUTERNAME;os=[Environment]::OSVersion.VersionString;architecture=$env:PROCESSOR_ARCHITECTURE;source_verified=$true;results=@{}}
 foreach($config in @('debug','release')){
  $log=Join-Path $root ($config+'.log');$started=Get-Date
  $ErrorActionPreference='Continue'
  & swift test --jobs 2 -c $config 2>&1 | Out-File $log -Encoding utf8
  $code=$LASTEXITCODE;$ErrorActionPreference='Stop'
  $report.results[$config]=@{exit_status=$code;elapsed_seconds=((Get-Date)-$started).TotalSeconds;log=$log}
  $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'test-status.json') -Encoding utf8
  Write-Output ($config+' EXIT='+$code)
 }
 if($report.results.debug.exit_status -ne 0 -or $report.results.release.exit_status -ne 0){exit 1}
 Write-Output 'WINDOWS_TESTS_COMPLETE'
}finally{Pop-Location}
