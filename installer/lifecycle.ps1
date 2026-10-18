function Stop-MenuHost {
    # Only this user's MagicC COM server; never restart Explorer or other apps.
    $session = (Get-Process -Id $PID).SessionId
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'dllhost.exe'")
    $servers = @($processes | Where-Object {
        $_.SessionId -eq $session -and
        $_.CommandLine -match '/Processid:\{79DCDF77-E582-4AA8-BAAC-EF6C3E11A728\}'
    })
    foreach ($server in $servers) {
        $owner = Invoke-CimMethod -InputObject $server -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        if ($owner.Sid -ne $sid) { continue }
        $children = @($processes | Where-Object {
            $_.ParentProcessId -eq $server.ProcessId -and $_.SessionId -eq $session
        })
        foreach ($process in ($children + @($server))) {
            $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction SilentlyContinue
            if ($owner.Sid -eq $sid) {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Stop-InstalledMagicC([string]$directory) {
    $exe = [IO.Path]::GetFullPath((Join-Path $directory 'MagicC.exe'))
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'MagicC.exe'" | Where-Object {
        $_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath) -eq $exe
    })
    foreach ($process in $processes) {
        $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        if ($owner.Sid -ne $sid) { throw 'Cannot update MagicC while another user is running this installation.' }
        $running = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
        if ($running -and $running.CloseMainWindow()) { $null = $running.WaitForExit(3000) }
    }
    # Older versions have no shutdown command; target their exact executable path.
    foreach ($process in $processes) {
        $running = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
        if ($running -and -not $running.HasExited) {
            $running.Kill()
            if (-not $running.WaitForExit(5000)) { throw 'MagicC did not exit.' }
        }
    }
}

function Assert-InstallFilesAvailable([string]$directory) {
    $names = @('MagicC.exe','MagicCShell.dll','MagicC.ico','MagicC.Menu.msix',
               'MagicC.cer','menu.ps1','trust.ps1','lifecycle.ps1','Uninstall.exe')
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $locked = @()
        foreach ($name in $names) {
            $path = Join-Path $directory $name
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            try {
                $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                $stream.Dispose()
            } catch { $locked += $name }
        }
        if (-not $locked.Count) { return }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    throw ('Files still in use or not writable: ' + ($locked -join ', '))
}
