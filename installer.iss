#ifndef AppVer
  #define AppVer "1.0.0"
#endif

[Setup]
AppId={{f64fa50b-b4ea-45d9-92f9-c4a54ee64213}}
AppName=Vidra
AppVersion={#AppVer}
AppVerName=Vidra {#AppVer}
AppPublisher=Chomusuke
AppPublisherURL=https://github.com/chomusuke-mk/vidra
AppSupportURL=https://github.com/chomusuke-mk/vidra/issues
AppUpdatesURL=https://github.com/chomusuke-mk/vidra/releases
AppContact=7k9mc4urn@mozmail.com
AppComments=Cross-platform playlist-aware media downloader.
AppCopyright=Copyright (c) 2026 Chomusuke
AppReadmeFile=README.md

DefaultDirName={localappdata}\Programs\Vidra
DefaultGroupName=Vidra
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableDirPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
OutputDir=dist
OutputBaseFilename=vidra-windows
SetupIconFile=assets\icon\icon.ico
WizardStyle=modern
LicenseFile=LICENSE
InfoBeforeFile=third_party_licenses\THIRD_PARTY_LICENSES.txt
UninstallDisplayIcon={app}\vidra.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DirExistsWarning=no
UsePreviousAppDir=yes
UsePreviousTasks=yes
Compression=lzma2/ultra64
SolidCompression=yes
RestartIfNeededByRun=no
CloseApplications=force
CloseApplicationsFilter=vidra.exe
SetupLogging=yes
ChangesAssociations=no
VersionInfoVersion={#AppVer}.0
VersionInfoCompany=Chomusuke
VersionInfoDescription=Vidra Installer
VersionInfoProductName=Vidra
VersionInfoProductVersion={#AppVer}
SetupMutex=SetupMutex{#SetupSetting("AppId")}

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Vidra"; Filename: "{app}\vidra.exe"; IconFilename: "{app}\vidra.exe"
Name: "{userdesktop}\Vidra"; Filename: "{app}\vidra.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create desktop icon"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Run]
Filename: "{app}\vidra.exe"; Description: "Launch Vidra"; Flags: nowait postinstall skipifsilent