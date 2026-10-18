# Run with Windows PowerShell. Creates isolated executable fixtures under build/.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'installer\lifecycle.ps1')
$testRoot = Join-Path $PSScriptRoot ('build\upgrade-test-' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $testRoot 'target'
$other = Join-Path $testRoot 'other'
$null = New-Item -ItemType Directory -Path $target,$other
$targetExe = Join-Path $target 'MagicC.exe'
$otherExe = Join-Path $other 'MagicC.exe'
$process1 = $null
$process2 = $null
$lock = $null
try {
    Add-Type -TypeDefinition 'public class UpgradeFixture { public static void Main() { System.Threading.Thread.Sleep(System.Threading.Timeout.Infinite); } }' -OutputAssembly $targetExe -OutputType WindowsApplication
    Copy-Item -LiteralPath $targetExe -Destination $otherExe
    $before = (Get-FileHash -LiteralPath $targetExe).Hash
    $process1 = Start-Process -FilePath $targetExe -WindowStyle Hidden -PassThru
    $process2 = Start-Process -FilePath $otherExe -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 300
    Stop-InstalledMagicC $target
    if (-not $process1.WaitForExit(5000)) { throw 'Old target executable was not stopped.' }
    $process2.Refresh()
    if ($process2.HasExited) { throw 'Executable from another directory was stopped.' }
    Assert-InstallFilesAvailable $target
    $lock = [IO.File]::Open($targetExe, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $failed = $false
    try { Assert-InstallFilesAvailable $target } catch { $failed = $true }
    if (-not $failed) { throw 'Locked executable was incorrectly allowed.' }
    $lock.Dispose()
    $lock = $null
    if ((Get-FileHash -LiteralPath $targetExe).Hash -ne $before) { throw 'Preflight changed existing executable bytes.' }
    Assert-InstallFilesAvailable $target
    Write-Output 'PASS: target process closed; other directory untouched; lock rejected; old file bytes preserved; retry succeeds.'
} finally {
    if ($lock) { $lock.Dispose() }
    foreach ($process in @($process1,$process2)) {
        if ($process) {
            $process.Refresh()
            if (-not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(5000) }
        }
    }
}
