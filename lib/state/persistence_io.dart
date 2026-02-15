import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'persistence.dart';

class _FilePersistence implements BudgetPersistence {
  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;

    final String dirPath;
    if (Platform.isWindows) {
      // Use custom path for Windows: AppData\Roaming\Budget_Calendar
      final appData = Platform.environment['APPDATA'];
      if (appData == null) throw Exception('APPDATA environment variable not found');
      dirPath = '$appData${Platform.pathSeparator}Budget_Calendar';
    } else {
      // Use standard path for other platforms
      final dir = await getApplicationSupportDirectory();
      dirPath = dir.path;
    }

    _file = File('$dirPath${Platform.pathSeparator}budget_data.json');
    return _file!;
  }

  @override
  Future<String?> read() async {
    final file = await _getFile();
    if (!await file.exists()) {
      // Try to migrate from old location
      await _migrateFromOldLocation();
      if (!await file.exists()) return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String contents) async {
    final file = await _getFile();
    await file.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<void> _migrateFromOldLocation() async {
    try {
      // Try to find data in old location
      final oldDir = await getApplicationSupportDirectory();
      final oldFile = File('${oldDir.path}${Platform.pathSeparator}budget_data.json');

      if (await oldFile.exists()) {
        final contents = await oldFile.readAsString();
        final newFile = await _getFile();
        await newFile.create(recursive: true);
        await newFile.writeAsString(contents);
      }
    } catch (_) {
      // Migration failed, continue without old data
    }
  }
}

BudgetPersistence createPersistenceImpl() => _FilePersistence();
