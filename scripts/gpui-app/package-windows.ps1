<# Compose already-built release components. Output must be new for rollback. #>
param(
    [Parameter(Mandatory=$true)][string]$RustBinary,
    [Parameter(Mandatory=$true)][string]$CompanionDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputDirectory){throw 'Output must be new; preserve previous installation for rollback'}
foreach($source in @($RustBinary,(Join-Path $CompanionDirectory 'ExplorerBackend.exe'),(Join-Path $CompanionDirectory 'WindowsPreviewHost.exe'))){
    if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing release component: $source"}
}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
Copy-Item -LiteralPath $RustBinary -Destination (Join-Path $OutputDirectory 'MacSpaceSniffer.exe')
foreach($name in @('ExplorerBackend.exe','WindowsPreviewHost.exe')){Copy-Item -LiteralPath (Join-Path $CompanionDirectory $name) -Destination $OutputDirectory}
$dlls=@(Get-ChildItem -LiteralPath $CompanionDirectory -Filter '*.dll' -File)
if(!$dlls.Count){throw 'No Swift runtime DLLs supplied'}
$dlls | Copy-Item -Destination $OutputDirectory
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Copy-Item -LiteralPath (Join-Path $repo 'gpui-app\assets\fonts\OFL.txt') -Destination (Join-Path $OutputDirectory 'NotoSansKR-OFL.txt')
$mcp=Join-Path $OutputDirectory 'MCP'
New-Item -ItemType Directory -Path $mcp | Out-Null
foreach($name in @('space_sniffer_mcp.py','control_transport.py')){Copy-Item -LiteralPath (Join-Path $repo "scripts\mcp\$name") -Destination $mcp}
$exe=Join-Path $OutputDirectory 'MacSpaceSniffer.exe'
$probe=Start-Process -FilePath $exe -ArgumentList @('--qa-output','unused') -Wait -PassThru
if($probe.ExitCode -ne 64){throw 'Release did not reject acceptance commands'}
$files=@(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File | ForEach-Object {@{path=$_.FullName.Substring($OutputDirectory.Length).TrimStart('\');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()}})
@{version='0.3.0';bundleId='local.macspacesniffer.app';qaCommandsRejected=$true;authenticode=(Get-AuthenticodeSignature -LiteralPath $exe).Status.ToString();files=$files} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($OutputDirectory+'.manifest.json') -Encoding UTF8
Compress-Archive -LiteralPath $OutputDirectory -DestinationPath ($OutputDirectory+'.zip')
Write-Output "Packaged: $OutputDirectory"
