param(
    [switch]$Execute,
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'

function Write-Action {
    param(
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Execute) {
        Write-Host "[EXEC] $Message"
    } else {
        Write-Host "[SIMULACAO] $Message"
    }
}

function Invoke-Uninstall {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )

    Write-Action "Desinstalar ${Name}: $FilePath $($ArgumentList -join ' ')"
    if (-not $Execute) {
        return $true
    }

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru
    Write-Host "Codigo de saida de ${Name}: $($process.ExitCode)"
    return ($process.ExitCode -in @(0, 1605, 3010))
}

function Remove-ResidualPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Action "Remover pasta residual: $Path"
        if ($Execute) {
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Host "[AVISO] Falha ao remover pasta residual: $Path"
                Write-Host "[AVISO] $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "[OK] Pasta ausente: $Path"
    }
}

function Remove-ResidualRegistryKey {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Action "Remover chave residual: $Path"
        if ($Execute) {
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Host "[AVISO] Falha ao remover chave residual: $Path"
                Write-Host "[AVISO] $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "[OK] Chave ausente: $Path"
    }
}

function Stop-TargetProcesses {
    param(
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    foreach ($name in $Names) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($process in $processes) {
            Write-Action "Encerrar processo $($process.ProcessName) PID $($process.Id)"
            if ($Execute) {
                Stop-Process -Id $process.Id -Force
            }
        }
    }
}

function Get-MsiArgs {
    param(
        [Parameter(Mandatory = $true)][string]$ProductCode
    )

    $args = @('/X', $ProductCode, '/norestart')
    if ($Silent) {
        $args += '/qn'
    } else {
        $args += '/passive'
    }
    return $args
}

$targets = @(
    @{
        Name = 'Java 8 Update 161'
        Type = 'Msi'
        ProductCode = '{26A24AE4-039D-4CA4-87B4-2F32180161F0}'
        Processes = @('java', 'javaw', 'jp2launcher', 'jusched')
        ResidualPaths = @('C:\Program Files (x86)\Java\jre1.8.0_161')
        RegistryKeys = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{26A24AE4-039D-4CA4-87B4-2F32180161F0}')
    },
    @{
        Name = 'Java 10'
        Type = 'Msi'
        ProductCode = '{EECB2736-D013-5AC5-9917-7656712F6931}'
        Processes = @('java', 'javaw', 'jp2launcher')
        ResidualPaths = @('C:\Program Files\Java\jre-10.0.2')
        RegistryKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{EECB2736-D013-5AC5-9917-7656712F6931}')
    },
    @{
        Name = 'JDK 10'
        Type = 'Msi'
        ProductCode = '{71307D56-8005-5F5E-9227-BFA2754D6E54}'
        Processes = @('java', 'javaw', 'javac', 'javadoc', 'jshell')
        ResidualPaths = @('C:\Program Files\Java\jdk-10.0.2')
        RegistryKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{71307D56-8005-5F5E-9227-BFA2754D6E54}')
    },
    @{
        Name = 'Microsoft Silverlight'
        Type = 'Msi'
        ProductCode = '{89F4137D-6C26-4A84-BDB8-2E5A4BB71E00}'
        Processes = @('Silverlight.Configuration', 'sllauncher')
        ResidualPaths = @('C:\Program Files (x86)\Microsoft Silverlight')
        RegistryKeys = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{89F4137D-6C26-4A84-BDB8-2E5A4BB71E00}')
    },
    @{
        Name = 'Mobizen'
        Type = 'Msi'
        ProductCode = '{BA0D3A44-BCEE-4C8B-BCD4-F7F1E64F41E3}'
        Processes = @('Mobizen', 'MobizenService', 'MobizenTray', 'rsautoup', 'RSZManager')
        ResidualPaths = @('C:\Program Files (x86)\RSUPPORT\Mobizen', 'C:\Program Files (x86)\RSUPPORT\MobizenService', "$env:APPDATA\Rsupport")
        RegistryKeys = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{BA0D3A44-BCEE-4C8B-BCD4-F7F1E64F41E3}')
    },
    @{
        Name = 'MicroStrategy Desktop'
        Type = 'Exe'
        FilePath = 'C:\Program Files\MicroStrategy\Desktop\uninstall\DesktopSetup.exe'
        Arguments = @('-L1033')
        Processes = @('MicroStrategy', 'DesktopSetup')
        ResidualPaths = @('C:\Program Files\MicroStrategy\Desktop', "$env:APPDATA\MicroStrategy")
        RegistryKeys = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{CE4E5307-2A7F-4DE2-A66D-9B198829A688}', 'HKLM:\SOFTWARE\MicroStrategy', 'HKLM:\SOFTWARE\WOW6432Node\MicroStrategy')
    },
    @{
        Name = 'Foxit Reader - chaves orfas'
        Type = 'RegistryOnly'
        Processes = @('FoxitReader', 'FoxitPDFReader', 'FoxitUpdater')
        ResidualPaths = @()
        RegistryKeys = @('HKLM:\SOFTWARE\WOW6432Node\Foxit Software\Foxit Reader', 'HKLM:\SOFTWARE\WOW6432Node\Foxit Software\Foxit Update')
    }
)

Write-Host "limpeza_residual.ps1"
Write-Host "Modo: $(if ($Execute) { 'EXECUCAO' } else { 'SIMULACAO' })"
Write-Host "Use -Execute para aplicar. Use -Silent junto com -Execute para MSI silencioso."
Write-Host ""

foreach ($target in $targets) {
    Write-Host "== $($target.Name) =="

    Stop-TargetProcesses -Names $target.Processes

    $uninstallOk = $true
    if ($target.Type -eq 'Msi') {
        $uninstallOk = Invoke-Uninstall -Name $target.Name -FilePath 'msiexec.exe' -ArgumentList (Get-MsiArgs -ProductCode $target.ProductCode)
    } elseif ($target.Type -eq 'Exe') {
        if (Test-Path -LiteralPath $target.FilePath) {
            $uninstallOk = Invoke-Uninstall -Name $target.Name -FilePath $target.FilePath -ArgumentList $target.Arguments
        } else {
            Write-Host "[AVISO] Desinstalador ausente: $($target.FilePath)"
        }
    } else {
        Write-Host "Sem desinstalador: limpeza apenas de registro residual."
    }

    if ($uninstallOk) {
        foreach ($path in $target.ResidualPaths) {
            Remove-ResidualPath -Path $path
        }

        foreach ($key in $target.RegistryKeys) {
            Remove-ResidualRegistryKey -Path $key
        }
    } else {
        Write-Host "[AVISO] Limpeza residual ignorada para $($target.Name) porque o desinstalador nao confirmou sucesso."
    }

    Write-Host ""
}

Write-Host "Concluido. Reexecute o inventario depois da limpeza para confirmar o estado final."
