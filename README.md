# BudgetCalendar

Flutter port of the legacy `Budget Calendar` Python/Tkinter app.

## Features
- Month view calendar
- Per-day income and expense entries (add/edit/delete)
- Monthly totals (income, expenses, balance)
- Running balance (hover a day on desktop/web)
- Dark mode (persisted)

## Data
Data is stored as JSON (`budget_data.json`) in the platform app-support location (or browser storage on web).

## Development
Requirements:
- Flutter SDK (tested with Flutter 3.35.x / Dart 3.9.x)

Run (Windows example):
```powershell
flutter pub get
flutter run -d windows
```

## Windows Installer (Inno Setup)
Requirements:
- Inno Setup 6 (`ISCC.exe`)

Build release + installer in one command:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_installer.ps1
```

Optional flags:
```powershell
# Override semantic version in installer filename/metadata
powershell -ExecutionPolicy Bypass -File .\scripts\build_installer.ps1 -AppVersion 1.2.3

# Build debug binaries before packaging (normally use release)
powershell -ExecutionPolicy Bypass -File .\scripts\build_installer.ps1 -Configuration debug

# Provide explicit ISCC path if Inno Setup is not on PATH
powershell -ExecutionPolicy Bypass -File .\scripts\build_installer.ps1 -IsccPath "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

Installer output:
- `dist\installer\BudgetCalendar-Setup-v<version>.exe`

## Repo Notes
- `reference/` is ignored via `.gitignore` (it contains the legacy Python source and assets used for porting).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
