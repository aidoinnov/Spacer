<# Primary Windows x64 GPUI composition. Run in a VS x64 Developer PowerShell. #>
param(
    [Parameter(Mandatory=$true)][string]$SwiftBin,
    [Parameter(Mandatory=$true)][string]$SwiftRuntimeDirectory,
    [string]$BuildRoot=(Join-Path $env:TEMP 'space-sniffer-gpui-build'),
    [int]$Jobs=4
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
foreach($tool in @('cl.exe','rc.exe')){if(!(Get-Command $tool -ErrorAction SilentlyContinue)){throw "Run in a VS x64 Developer PowerShell: missing $tool"}}
if($Jobs -lt 1 -or $Jobs -gt 16){throw 'Jobs must be 1..16'}
$swift=Join-Path $SwiftBin 'swift.exe'
$cargo=Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
if(!(Test-Path -LiteralPath $swift) -or !(Test-Path -LiteralPath $cargo)){throw 'Swift/Rust toolchain path missing'}
if(!(Test-Path -LiteralPath (Join-Path $SwiftRuntimeDirectory 'swiftCore.dll'))){throw 'Matching Swift runtime directory required'}
$env:Path=$SwiftBin+';'+$SwiftRuntimeDirectory+';'+$env:Path
$env:SPACE_SNIFFER_BUNDLE_ID='local.macspacesniffer.app'
$env:CARGO_INCREMENTAL='0';$env:CARGO_TARGET_DIR=Join-Path $BuildRoot 'target'
function Invoke-Tool([string]$File,[string[]]$Arguments){
 $prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try {& $File @Arguments 2>&1|ForEach-Object {$_.ToString()};$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
 if($code -ne 0){throw "Native build tool failed ($code): $File"}
}
$faces=Get-Content (Join-Path $repo 'gpui-app\assets\fonts\static-faces.json') -Raw|ConvertFrom-Json
foreach($face in $faces.faces){$font=Join-Path $repo ('gpui-app\assets\fonts\'+$face.path);if((Get-FileHash -LiteralPath $font -Algorithm SHA256).Hash.ToLower() -ne $face.sha256){throw 'Static font source hash mismatch'}}
$native=Join-Path $BuildRoot 'explorer-build';$package=Join-Path $repo 'Packages\SpaceSnifferExplorerBridge'
Invoke-Tool -File $cargo -Arguments @('+1.97.0','build','--release','--locked','--manifest-path',(Join-Path $repo 'gpui-app\cli\Cargo.toml'),'--jobs',$Jobs.ToString())
Invoke-Tool -File $swift -Arguments @('build','--package-path',$package,'--scratch-path',$native,'-c','release','--product','ExplorerBackend','--jobs','2')
Invoke-Tool -File $cargo -Arguments @('+1.97.0','build','--release','--locked','--manifest-path',(Join-Path $repo 'gpui-app\Cargo.toml'),'--jobs',$Jobs.ToString())
$companions=Join-Path $BuildRoot 'companions';New-Item -ItemType Directory -Path $companions -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $native 'release\ExplorerBackend.exe') -Destination $companions -Force
Get-ChildItem -LiteralPath $SwiftRuntimeDirectory -Filter '*.dll' -File|Copy-Item -Destination $companions -Force
Invoke-Tool -File (Join-Path $repo 'gpui-app\native\windows-preview\build.cmd') -Arguments @($companions)
$version=[Regex]::Match((Get-Content (Join-Path $repo 'gpui-app\Cargo.toml') -Raw),'(?m)^version = "([^"]+)"').Groups[1].Value
$output=Join-Path $repo ('dist\gpui-builds\'+$version+'-windows-x64-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
& (Join-Path $repo 'scripts\gpui-app\package-windows.ps1') -RustBinary (Join-Path $env:CARGO_TARGET_DIR 'release\space-sniffer-gpui.exe') -CliBinary (Join-Path $env:CARGO_TARGET_DIR 'release\spacer-cli.exe') -CompanionDirectory $companions -OutputDirectory $output
Write-Output "Built: $output"
