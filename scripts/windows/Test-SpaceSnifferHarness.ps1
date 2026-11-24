#requires -Version 5.1
# Read-only PowerShell AST validation; does not execute SpaceSniffer or the harness.
[CmdletBinding()]
param([string]$Path = (Join-Path $PSScriptRoot 'Invoke-SpaceSnifferRuntimeQA.ps1'))
$Tokens=$null; $Errors=$null
$Ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Path).ProviderPath, [ref]$Tokens, [ref]$Errors)
if ($Errors.Count -gt 0) { $Errors | Format-List; exit 1 }
[pscustomobject]@{ parser='System.Management.Automation.Language.Parser'; powershell=$PSVersionTable.PSVersion.ToString(); source=$Ast.Extent.File; parse_errors=$Errors.Count; executed_target=$false } | ConvertTo-Json
