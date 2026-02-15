import 'package:shared_preferences/shared_preferences.dart';

import 'persistence.dart';

class _PrefsPersistence implements BudgetPersistence {
  static const _key = 'budget_data.json';

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> write(String contents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, contents);
  }
}

BudgetPersistence createPersistenceImpl() => _PrefsPersistence();

