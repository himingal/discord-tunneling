; ============================================================
;  Discord Single-Tunneling - Setup Script (Inno Setup)
;  Compile this file with Inno Setup (jrsoftware.org/isinfo.php)
;  to generate a real .exe installer, with the standard Windows
;  wizard screens (Next > Next > Finish).
; ============================================================

#define MyAppName "Discord Single-Tunneling"
#define MyAppVersion "3.7"
#define MyAppPublisher "mingal"
#define MyAppExeName "installer.ps1"

[Setup]
AppId={{B1A9F5D2-7C3E-4F0A-9D21-6E4C8A0F2B77}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=DiscordTunneling-Setup
SetupIconFile=assets\app_settings.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Place these files in the same folder as this .iss before compiling:
Source: "installer.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\app.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "assets\app_settings.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "assets\app_logo.png"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "assets\avatar.png"; DestDir: "{app}\assets"; Flags: ignoreversion
; If you already have sing-box.exe downloaded, you can include it here too (optional):
; Source: "sing-box.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "powershell.exe"; \
    Parameters: "-WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\{#MyAppExeName}"""; \
    IconFilename: "{app}\assets\app_settings.ico"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "powershell.exe"; \
    Parameters: "-WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\{#MyAppExeName}"""; \
    IconFilename: "{app}\assets\app_settings.ico"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "powershell.exe"; \
    Parameters: "-WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\{#MyAppExeName}"""; \
    WorkingDir: "{app}"; Description: "Run the tunnel setup now"; \
    Flags: postinstall skipifsilent runascurrentuser
