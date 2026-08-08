$ErrorActionPreference = 'Stop';

# --- Script de desinstalación para Vidra ---

$packageName = 'vidra'
$installerType = 'exe'
$silentArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
$softwareName = 'Vidra*'

# Buscamos la llave de registro de InnoSetup para Vidra
[array]$key = Get-UninstallRegistryKey -SoftwareName $softwareName
if ($key.Count -eq 1) {
    # InnoSetup a veces envuelve la ruta en comillas. Las removemos.
    $uninstallString = $key.UninstallString -replace '"', ''
    
    if ($uninstallString -ne $null -and $uninstallString -ne '') {
        Write-Host "Found uninstaller: $uninstallString"
        Uninstall-ChocolateyPackage -PackageName $packageName -FileType 'exe' -SilentArgs $silentArgs -File $uninstallString
    }
} elseif ($key.Count -eq 0) {
    Write-Warning "Uninstall key not found for '$softwareName'."
} else {
    Write-Warning "There are multiple entries for '$softwareName'. Please check the registry manually."
}
