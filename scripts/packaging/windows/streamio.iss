; Inno Setup script for the Streamio Windows installer.
; Not run by hand — scripts/package-windows.ps1 compiles it with ISCC and
; passes SourceDir / OutputDir / AppVersion / OutputName in on the command line.
;
;   iscc /DAppVersion=1.4.2 /DSourceDir=... /DOutputDir=... /DOutputName=... streamio.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #error SourceDir must be defined (the flutter build windows Release folder)
#endif
#ifndef OutputDir
  #define OutputDir "dist"
#endif
#ifndef OutputName
  #define OutputName "streamio-setup"
#endif
#ifndef IconFile
  #define IconFile ""
#endif

#define AppName "Streamio"
#define AppExeName "streamio.exe"

[Setup]
; Never reuse this GUID for another application — it is what lets an upgrade
; replace the previous install instead of piling up a second copy.
AppId={{7A2E1F84-9C3B-4E5D-8A16-3F5C2D9B7E01}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
AppPublisher=Streamio
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
#if IconFile != ""
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile={#IconFile}
#endif
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 64-bit only, matching the only Windows target Flutter builds here.
; 'x64' rather than 6.3's 'x64compatible' so older Inno Setup 6.x still compiles this.
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Per-machine when the user can elevate, per-user when they can't — so someone
; without an admin account can still install it.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter Release folder: streamio.exe, its DLLs (including the
; bundled mpv), and data\ with the assets and ICU data. It only runs with
; those laid out beside it, so the recursion here is not optional.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
