#define AppName "BudgetCalendar"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef BuildDir
  #define BuildDir "..\\build\\windows\\x64\\runner\\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\\dist\\installer"
#endif

[Setup]
AppId={{A22B4E91-97F4-4F25-B41F-70C6F35B93B4}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=BudgetCalendar
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=BudgetCalendar-Setup-v{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\\windows\\runner\\resources\\app_icon.ico
UninstallDisplayIcon={app}\budget_calendar.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\budget_calendar.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\budget_calendar.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\budget_calendar.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
