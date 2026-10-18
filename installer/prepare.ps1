param([Parameter(Mandatory=$true)][string]$InstallRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lifecycle.ps1')
try {
    $directory = [IO.Path]::GetFullPath($InstallRoot)
    if (-not [IO.Path]::IsPathRooted($InstallRoot) -or $directory -eq [IO.Path]::GetPathRoot($directory)) {
        throw 'Invalid installation directory.'
    }
    if (-not (Test-Path -LiteralPath $directory)) { exit 0 }
    Write-Output 'Closing the previous MagicC installation...'
    Stop-InstalledMagicC $directory
    if ((Test-Path -LiteralPath (Join-Path $directory 'MagicC.exe')) -or
        (Test-Path -LiteralPath (Join-Path $directory 'MagicCShell.dll'))) {
        Write-Output 'Releasing MagicC Explorer menu...'
        Stop-MenuHost
        # Run the new removal code, never the old installer/menu script.
        Get-AppxPackage -Name 'MagicC.Desktop' | Remove-AppxPackage
        $marker = Join-Path $directory 'modern-menu.enabled'
        if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
    }
    Write-Output 'Checking installation files are available...'
    Assert-InstallFilesAvailable $directory
    Write-Output 'Ready to update MagicC.'
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
