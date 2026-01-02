[Setup]
AppId={{8A1B20DA-0615-43AF-A7D5-87D090F2CB25}}
AppName=Vidra
AppVersion=1.0.0
AppVerName=Vidra 1.0.0
AppPublisher=Chomusuke
AppPublisherURL=https://github.com/chomusuke-mk/vidra
AppSupportURL=https://github.com/chomusuke-mk/vidra/issues
AppUpdatesURL=https://github.com/chomusuke-mk/vidra/releases
AppContact=7k9mc4urn@mozmail.com
AppComments=Cross-platform playlist-aware media downloader.
AppCopyright=Copyright (c) 2025 Chomusuke
DefaultDirName={userappdata}\Vidra
DefaultGroupName=Vidra
DisableProgramGroupPage=yes
OutputDir=build\installer
OutputBaseFilename=Vidra-Installer-1.0.0
SetupIconFile=assets\icon\icon.ico
WizardStyle=modern
LicenseFile=LICENSE
InfoBeforeFile=THIRD_PARTY_LICENSES.txt
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
VersionInfoVersion=1.0.0.0
VersionInfoCompany=Chomusuke
VersionInfoDescription=Vidra Installer
VersionInfoProductName=Vidra
VersionInfoProductVersion=1.0.0

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "THIRD_PARTY_LICENSES.md"; DestDir: "{app}"; DestName: "THIRD_PARTY_LICENSES.txt"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Vidra"; Filename: "{app}\vidra.exe"; IconFilename: "{app}\vidra.exe"
Name: "{group}\Uninstall Vidra"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Vidra"; Filename: "{app}\vidra.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create desktop icon"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Run]
Filename: "{app}\vidra.exe"; Description: "Launch Vidra"; Flags: nowait postinstall skipifsilent