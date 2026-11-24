# Cleans only the owned VHD fixture whose manifest was created by the acceptance test.
param([Parameter(Mandatory=$true)][string]$Manifest)
$ErrorActionPreference='Stop'
$m=Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
if($m.removed){Write-Output 'Fixture already removed';exit 0}
$root=[IO.Path]::GetFullPath($m.root)
$temp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
if(!$m.owned -or !$root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or !(Split-Path $root -Leaf).StartsWith('sniffer-owned-mount-')){throw 'Not an owned acceptance fixture'}
$image=[IO.Path]::GetFullPath($m.image)
if($image -ne (Join-Path $root 'owned.vhd')){throw 'Unexpected image path'}
if(Test-Path -LiteralPath $image){
    $state=Get-DiskImage -ImagePath $image
    if($state.Attached){
        $disk=$state | Get-Disk
        if($disk.BusType -ne 'File Backed Virtual' -or $disk.Size -gt 70MB){throw 'Unexpected owned disk identity'}
        $mount=[IO.Path]::GetFullPath($m.mount).TrimEnd('\')+'\'
        if(!$mount.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Mount escapes fixture'}
        foreach($partition in @($disk | Get-Partition)){
            if($partition.AccessPaths -contains $mount){$partition | Remove-PartitionAccessPath -AccessPath $mount}
        }
        Dismount-DiskImage -ImagePath $image
        if((Get-DiskImage -ImagePath $image).Attached){throw 'Owned image still mounted'}
    }
}
if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
$m.removed=$true
$m | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Manifest -Encoding UTF8
Write-Output 'Owned acceptance fixture removed'
