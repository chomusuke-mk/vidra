$ErrorActionPreference = 'Stop';

# --- Paquete Chocolatey para Vidra ---
# Vidra usa InnoSetup para su instalador, por lo que admite banderas /VERYSILENT de forma nativa.

$packageName  = 'vidra'
$toolsDir     = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url64        = 'https://github.com/chomusuke-mk/vidra/releases/download/__APP_VERSION__/vidra-windows.exe'
$installerType= 'exe'
$checksum     = '__SHA256_HASH__'
$checksumType = 'sha256'

# ARGUMENTOS SILENCIOSOS REQUERIDOS POR CHOCOLATEY PARA INNOSETUP
# Chocolatey internamente agregará /VERYSILENT /SUPPRESSMSGBOXES /NORESTART pero los explicitamos
$silentArgs   = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'

$packageArgs = @{
  packageName   = $packageName
  unzipLocation = $toolsDir
  fileType      = $installerType
  url64bit      = $url64
  checksum64    = $checksum
  checksumType64= $checksumType
  silentArgs    = $silentArgs
  validExitCodes= @(0, 3010, 1641, 1638)
}

Install-ChocolateyPackage @packageArgs
