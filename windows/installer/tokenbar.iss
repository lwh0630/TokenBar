; Inno Setup script for the TokenBar Windows installer.
;
; Built by .github/workflows/release.yml (and ci.yml) with, for example:
;   ISCC /DAppVersion=1.0.0 /DNumericVersion=1.0.0.0 /DArch=x64 ^
;        /DSourceDir=..\..\build\windows\x64\runner\Release ^
;        /DOutputDir=..\..\dist /DOutputName=tokenbar-v1.0.0-windows-x64-setup ^
;        windows\installer\tokenbar.iss
;
; Arch is "x64" or "arm64". The installer is per-user by default (no admin
; rights, installs under %LOCALAPPDATA%\Programs) and lets the user choose an
; all-users install in the privileges dialog.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef NumericVersion
  #define NumericVersion "0.0.0.0"
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef OutputName
  #define OutputName "tokenbar-setup"
#endif

#define AppName "TokenBar"
#define AppExe "token_bar.exe"
#define AppUrl "https://github.com/lwh0630/TokenBar"

[Setup]
; Never change this GUID: it is how upgrades find the previous installation.
AppId={{6F1D6C2E-5B7B-4C58-9C1E-3E5B0A7F2D41}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#NumericVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} installer
AppPublisher=TokenBar contributors
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
; Close a running TokenBar during an upgrade and start it again afterwards.
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; "Launch at login" is a setting inside the app (it writes this Run value);
; make sure uninstalling leaves nothing behind.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "{#AppName}"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; The in-app updater runs this installer silently with /relaunch=1 after quitting the app, so the new
; version has to be started here (the normal post-install checkbox is skipped when silent).
Filename: "{app}\{#AppExe}"; Flags: nowait runasoriginaluser; Check: RelaunchRequested

[Code]
function RelaunchRequested: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;
