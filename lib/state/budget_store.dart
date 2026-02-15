import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../util/date_key.dart';
import 'persistence.dart';

enum EntryType { income, expense }

enum RecurrencePattern { none, weekly, biweekly, every4Weeks, monthly }

extension RecurrencePatternX on RecurrencePattern {
  String get storageKey {
    switch (this) {
      case RecurrencePattern.none:
        return 'none';
      case RecurrencePattern.weekly:
        return 'weekly';
      case RecurrencePattern.biweekly:
        return 'biweekly';
      case RecurrencePattern.every4Weeks:
        return 'every4weeks';
      case RecurrencePattern.monthly:
        return 'monthly';
    }
  }

  String get label {
    switch (this) {
      case RecurrencePattern.none:
        return 'No repeat';
      case RecurrencePattern.weekly:
        return 'Every week';
      case RecurrencePattern.biweekly:
        return 'Every 2 weeks';
      case RecurrencePattern.every4Weeks:
        return 'Every 4 weeks';
      case RecurrencePattern.monthly:
        return 'Every month';
    }
  }

  static RecurrencePattern fromStorage(String? value) {
    return RecurrencePattern.values.firstWhere(
      (v) => v.storageKey == value,
      orElse: () => RecurrencePattern.none,
    );
  }
}

class BudgetEntry {
  BudgetEntry({
    required this.name,
    required this.amountPennies,
    this.note = '',
  });

  final String name;
  final int amountPennies;
  final String note;

  BudgetEntry copyWith({String? name, int? amountPennies, String? note}) {
    return BudgetEntry(
      name: name ?? this.name,
      amountPennies: amountPennies ?? this.amountPennies,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'amount': amountPennies / 100.0,
    if (note.trim().isNotEmpty) 'note': note.trim(),
  };

  static BudgetEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final amount = value['amount'] ?? value['amount_pennies'];
    final note = value['note'];

    if (name is! String || name.trim().isEmpty) return null;
    final pennies = _amountAnyToPennies(amount);
    if (pennies == null || pennies <= 0) return null;

    return BudgetEntry(
      name: name.trim(),
      amountPennies: pennies,
      note: note is String ? note.trim() : '',
    );
  }

  static int? _amountAnyToPennies(Object? amount) {
    if (amount is int) return amount;
    if (amount is double) return (amount * 100).round();
    if (amount is num) return (amount.toDouble() * 100).round();
    if (amount is String) return BudgetStore.tryParseAmountToPennies(amount);
    return null;
  }
}

class BudgetEntryView {
  BudgetEntryView({
    required this.index,
    required this.name,
    required this.amountPennies,
    required this.note,
  });

  final int index;
  final String name;
  final int amountPennies;
  final String note;
}

class BudgetBackup {
  BudgetBackup({required this.createdAtIso, required this.dataJson});

  final String createdAtIso;
  final String dataJson;

  Map<String, Object?> toJson() => {
    'created_at': createdAtIso,
    'data_json': dataJson,
  };

  static BudgetBackup? fromJson(Object? value) {
    if (value is! Map) return null;
    final createdAt = value['created_at'];
    final dataJson = value['data_json'];
    if (createdAt is! String || dataJson is! String) return null;
    return BudgetBackup(createdAtIso: createdAt, dataJson: dataJson);
  }
}

class BudgetStore extends ChangeNotifier {
  BudgetStore._({
    required this.darkMode,
    required this.incomeColorLight,
    required this.incomeColorDark,
    required this.expenseColorLight,
    required this.expenseColorDark,
    required this.bothColorLight,
    required this.bothColorDark,
    required this.showRunningBalance,
    required this.showMonthBalance,
    required this.showDayRunningBalanceOnHover,
    required this.minimizeToTray,
    required this.weekStartDay,
    required this.highContrastMode,
    required this.textScaleFactor,
    required this.currencySymbol,
    required this.startingBalancePennies,
    required this.monthlyBudgetPennies,
    required this.panelOrderIds,
    required List<BudgetBackup> backups,
    required BudgetPersistence persistence,
    required Map<String, List<BudgetEntry>> income,
    required Map<String, List<BudgetEntry>> expenses,
  }) : _income = income,
       _expenses = expenses,
       _backups = backups,
       _persistence = persistence;

  final BudgetPersistence _persistence;

  bool darkMode;
  Color incomeColorLight;
  Color incomeColorDark;
  Color expenseColorLight;
  Color expenseColorDark;
  Color bothColorLight;
  Color bothColorDark;

  bool showRunningBalance;
  bool showMonthBalance;
  bool showDayRunningBalanceOnHover;
  bool minimizeToTray;
  int weekStartDay;

  bool highContrastMode;
  double textScaleFactor;

  String currencySymbol;
  int startingBalancePennies;
  int monthlyBudgetPennies;
  List<String> panelOrderIds;

  final List<BudgetBackup> _backups;
  final Map<String, List<BudgetEntry>> _income;
  final Map<String, List<BudgetEntry>> _expenses;
  int _metricsRevision = 0;

  static const List<String> _defaultPanelOrder = <String>[
    'date',
    'totals',
    'calendar',
  ];

  int get backupCount => _backups.length;
  int get metricsRevision => _metricsRevision;

  void _bumpMetricsRevision() {
    _metricsRevision += 1;
  }

  static Future<BudgetStore> load() async {
    final persistence = createPersistence();
    final loaded = await _loadJson(persistence);
    final settings = loaded['settings'];

    final darkMode = _getBool(settings, 'dark_mode', false);
    final incomeColorLight = _getColor(
      settings,
      'income_color_light',
      const Color(0xFF2E7D32),
    );
    final incomeColorDark = _getColor(
      settings,
      'income_color_dark',
      const Color(0xFF66BB6A),
    );
    final expenseColorLight = _getColor(
      settings,
      'expense_color_light',
      const Color(0xFFC62828),
    );
    final expenseColorDark = _getColor(
      settings,
      'expense_color_dark',
      const Color(0xFFEF5350),
    );
    final bothColorLight = _getColor(
      settings,
      'both_color_light',
      const Color(0xFFFFB74D),
    );
    final bothColorDark = _getColor(
      settings,
      'both_color_dark',
      const Color(0xFFFFB74D),
    );

    final showRunningBalance = _getBool(settings, 'show_running_balance', true);
    final showMonthBalance = _getBool(settings, 'show_month_balance', true);
    final showDayRunningBalanceOnHover = _getBool(
      settings,
      'show_day_running_balance_on_hover',
      true,
    );
    final minimizeToTray = _getBool(settings, 'minimize_to_tray', false);
    final weekStartDay = _sanitizeWeekStart(
      _getInt(settings, 'week_start_day', 1),
    );

    final highContrastMode = _getBool(settings, 'high_contrast_mode', false);
    final textScaleFactor = _sanitizeTextScale(
      _getDouble(settings, 'text_scale_factor', 1.0),
    );

    final currencySymbolRaw = _getString(settings, 'currency_symbol', '£');
    final currencySymbol = currencySymbolRaw.trim().isEmpty
        ? '£'
        : currencySymbolRaw.trim();

    final startingBalancePennies = _getInt(
      settings,
      'starting_balance_pennies',
      0,
    );
    final monthlyBudgetPennies = math.max(
      0,
      _getInt(settings, 'monthly_budget_pennies', 0),
    );
    final panelOrderIds = _sanitizePanelOrder(
      _getStringList(settings, 'panel_order'),
    );

    final backups = _parseBackups(settings);
    final income = _parseEntryMap(loaded['income']);
    final expenses = _parseEntryMap(loaded['expenses']);

    return BudgetStore._(
      darkMode: darkMode,
      incomeColorLight: incomeColorLight,
      incomeColorDark: incomeColorDark,
      expenseColorLight: expenseColorLight,
      expenseColorDark: expenseColorDark,
      bothColorLight: bothColorLight,
      bothColorDark: bothColorDark,
      showRunningBalance: showRunningBalance,
      showMonthBalance: showMonthBalance,
      showDayRunningBalanceOnHover: showDayRunningBalanceOnHover,
      minimizeToTray: minimizeToTray,
      weekStartDay: weekStartDay,
      highContrastMode: highContrastMode,
      textScaleFactor: textScaleFactor,
      currencySymbol: currencySymbol,
      startingBalancePennies: startingBalancePennies,
      monthlyBudgetPennies: monthlyBudgetPennies,
      panelOrderIds: panelOrderIds,
      backups: backups,
      persistence: persistence,
      income: income,
      expenses: expenses,
    );
  }

  @visibleForTesting
  static BudgetStore inMemory({bool darkMode = false}) {
    final p = _MemoryPersistence();
    return BudgetStore._(
      darkMode: darkMode,
      incomeColorLight: const Color(0xFF2E7D32),
      incomeColorDark: const Color(0xFF66BB6A),
      expenseColorLight: const Color(0xFFC62828),
      expenseColorDark: const Color(0xFFEF5350),
      bothColorLight: const Color(0xFFFFB74D),
      bothColorDark: const Color(0xFFFFB74D),
      showRunningBalance: true,
      showMonthBalance: true,
      showDayRunningBalanceOnHover: true,
      minimizeToTray: false,
      weekStartDay: 1,
      highContrastMode: false,
      textScaleFactor: 1.0,
      currencySymbol: '£',
      startingBalancePennies: 0,
      monthlyBudgetPennies: 0,
      panelOrderIds: List<String>.from(_defaultPanelOrder),
      backups: <BudgetBackup>[],
      persistence: p,
      income: <String, List<BudgetEntry>>{},
      expenses: <String, List<BudgetEntry>>{},
    );
  }

  static Map<String, List<BudgetEntry>> _parseEntryMap(Object? raw) {
    final out = <String, List<BudgetEntry>>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String) continue;
      if (DateKey.tryParse(key) == null) continue;
      if (value is! List) continue;
      final list = <BudgetEntry>[];
      for (final item in value) {
        final e = BudgetEntry.fromJson(item);
        if (e != null) list.add(e);
      }
      if (list.isNotEmpty) {
        out[key] = list;
      }
    }
    return out;
  }

  static List<BudgetBackup> _parseBackups(Object? settings) {
    if (settings is! Map) return <BudgetBackup>[];
    final backupsRaw = settings['backups'];
    if (backupsRaw is! List) return <BudgetBackup>[];

    final parsed = <BudgetBackup>[];
    for (final item in backupsRaw) {
      final b = BudgetBackup.fromJson(item);
      if (b != null) parsed.add(b);
    }
    return parsed;
  }

  static Future<Map<String, Object?>> _loadJson(
    BudgetPersistence persistence,
  ) async {
    try {
      final txt = await persistence.read();
      if (txt == null || txt.trim().isEmpty) {
        return {
          'income': <String, Object?>{},
          'expenses': <String, Object?>{},
          'settings': <String, Object?>{},
        };
      }
      final v = jsonDecode(txt);
      if (v is Map) {
        return v.map((k, v) => MapEntry(k.toString(), v))
            as Map<String, Object?>;
      }
    } catch (_) {
      // Fall through to empty.
    }

    return {
      'income': <String, Object?>{},
      'expenses': <String, Object?>{},
      'settings': <String, Object?>{},
    };
  }

  Map<String, Object?> toJson() => {
    'income': _income.map(
      (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()),
    ),
    'expenses': _expenses.map(
      (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()),
    ),
    'settings': {
      'dark_mode': darkMode,
      'income_color_light': colorToHex(incomeColorLight),
      'income_color_dark': colorToHex(incomeColorDark),
      'expense_color_light': colorToHex(expenseColorLight),
      'expense_color_dark': colorToHex(expenseColorDark),
      'both_color_light': colorToHex(bothColorLight),
      'both_color_dark': colorToHex(bothColorDark),
      'show_running_balance': showRunningBalance,
      'show_month_balance': showMonthBalance,
      'show_day_running_balance_on_hover': showDayRunningBalanceOnHover,
      'minimize_to_tray': minimizeToTray,
      'week_start_day': weekStartDay,
      'high_contrast_mode': highContrastMode,
      'text_scale_factor': textScaleFactor,
      'currency_symbol': currencySymbol,
      'starting_balance_pennies': startingBalancePennies,
      'monthly_budget_pennies': monthlyBudgetPennies,
      'panel_order': panelOrderIds,
      'backups': _backups.map((b) => b.toJson()).toList(),
    },
  };

  String exportJsonText() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  Future<void> _save() async {
    final txt = exportJsonText();
    try {
      await _persistence.write(txt);
    } catch (_) {
      // ignore write errors here; explicit features return status.
    }
  }

  Future<bool> _saveReturningSuccess() async {
    final txt = exportJsonText();
    try {
      await _persistence.write(txt);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _autoBackup(String reason) async {
    final raw = exportJsonText();
    _backups.add(
      BudgetBackup(
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
        dataJson: raw,
      ),
    );
    if (_backups.length > 20) {
      _backups.removeRange(0, _backups.length - 20);
    }
    await _save();
  }

  void toggleDarkMode() {
    darkMode = !darkMode;
    _save();
    notifyListeners();
  }

  bool hasIncome(String dayKey) => (_income[dayKey]?.isNotEmpty ?? false);
  bool hasExpense(String dayKey) => (_expenses[dayKey]?.isNotEmpty ?? false);

  int dayIncomePennies(String dayKey) {
    final list = _income[dayKey];
    if (list == null) return 0;
    return list.fold<int>(0, (sum, entry) => sum + entry.amountPennies);
  }

  int dayExpensePennies(String dayKey) {
    final list = _expenses[dayKey];
    if (list == null) return 0;
    return list.fold<int>(0, (sum, entry) => sum + entry.amountPennies);
  }

  int dayBalancePennies(String dayKey) {
    return dayIncomePennies(dayKey) - dayExpensePennies(dayKey);
  }

  int dayEntryCount(String dayKey) {
    final incomeCount = _income[dayKey]?.length ?? 0;
    final expenseCount = _expenses[dayKey]?.length ?? 0;
    return incomeCount + expenseCount;
  }

  List<BudgetEntryView> incomeForDay(String dayKey) {
    final list = _income[dayKey] ?? const <BudgetEntry>[];
    return List<BudgetEntryView>.generate(
      list.length,
      (i) => BudgetEntryView(
        index: i,
        name: list[i].name,
        amountPennies: list[i].amountPennies,
        note: list[i].note,
      ),
    );
  }

  List<BudgetEntryView> expenseForDay(String dayKey) {
    final list = _expenses[dayKey] ?? const <BudgetEntry>[];
    return List<BudgetEntryView>.generate(
      list.length,
      (i) => BudgetEntryView(
        index: i,
        name: list[i].name,
        amountPennies: list[i].amountPennies,
        note: list[i].note,
      ),
    );
  }

  Future<void> addEntry(
    String dayKey,
    EntryType type,
    BudgetEntry entry,
  ) async {
    final map = type == EntryType.income ? _income : _expenses;
    final list = map.putIfAbsent(dayKey, () => <BudgetEntry>[]);
    list.add(entry);
    _bumpMetricsRevision();
    await _save();
    notifyListeners();
  }

  Future<void> addEntryWithRecurrence(
    String dayKey,
    EntryType type,
    BudgetEntry entry,
    RecurrencePattern pattern,
    int occurrences,
  ) async {
    final keys = generateRecurringDateKeys(dayKey, pattern, occurrences);
    final map = type == EntryType.income ? _income : _expenses;
    for (final key in keys) {
      final list = map.putIfAbsent(key, () => <BudgetEntry>[]);
      list.add(entry.copyWith());
    }
    _bumpMetricsRevision();
    await _save();
    notifyListeners();
  }

  Future<void> updateEntry(
    String dayKey,
    EntryType type,
    int index,
    BudgetEntry entry,
  ) async {
    final map = type == EntryType.income ? _income : _expenses;
    final list = map[dayKey];
    if (list == null || index < 0 || index >= list.length) return;
    list[index] = entry;
    _bumpMetricsRevision();
    await _save();
    notifyListeners();
  }

  Future<void> deleteEntry(String dayKey, EntryType type, int index) async {
    final map = type == EntryType.income ? _income : _expenses;
    final list = map[dayKey];
    if (list == null || index < 0 || index >= list.length) return;
    list.removeAt(index);
    if (list.isEmpty) map.remove(dayKey);
    _bumpMetricsRevision();
    await _save();
    notifyListeners();
  }

  int sumMonthIncomePennies(DateTime month) =>
      _sumEntriesInRangePennies(_income, _monthStart(month), _monthEnd(month));
  int sumMonthExpensePennies(DateTime month) => _sumEntriesInRangePennies(
    _expenses,
    _monthStart(month),
    _monthEnd(month),
  );

  int runningBalancePennies(DateTime upToDay) {
    final d = DateTime(upToDay.year, upToDay.month, upToDay.day);
    final income = _sumEntriesInRangePennies(_income, DateTime(1900, 1, 1), d);
    final expenses = _sumEntriesInRangePennies(
      _expenses,
      DateTime(1900, 1, 1),
      d,
    );
    return startingBalancePennies + income - expenses;
  }

  static DateTime _monthStart(DateTime month) =>
      DateTime(month.year, month.month, 1);
  static DateTime _monthEnd(DateTime month) =>
      DateTime(month.year, month.month + 1, 0);

  static int _sumEntriesInRangePennies(
    Map<String, List<BudgetEntry>> map,
    DateTime start,
    DateTime end,
  ) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    var total = 0;
    for (final kv in map.entries) {
      final dt = DateKey.tryParse(kv.key);
      if (dt == null) continue;
      if (dt.isBefore(s) || dt.isAfter(e)) continue;
      for (final item in kv.value) {
        total += item.amountPennies;
      }
    }
    return total;
  }

  static int? tryParseAmountToPennies(String input) {
    final cleaned = input.trim().replaceAll('£', '').replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    final v = double.tryParse(cleaned);
    if (v == null) return null;
    return (v * 100).round();
  }

  static List<String> generateRecurringDateKeys(
    String startDayKey,
    RecurrencePattern pattern,
    int occurrences,
  ) {
    final start = DateKey.tryParse(startDayKey);
    if (start == null) return <String>[];

    final count = math.max(1, math.min(occurrences, 120));
    final keys = <String>[];

    for (var i = 0; i < count; i++) {
      late DateTime d;
      switch (pattern) {
        case RecurrencePattern.none:
          if (i > 0) continue;
          d = start;
        case RecurrencePattern.weekly:
          d = start.add(Duration(days: 7 * i));
        case RecurrencePattern.biweekly:
          d = start.add(Duration(days: 14 * i));
        case RecurrencePattern.every4Weeks:
          d = start.add(Duration(days: 28 * i));
        case RecurrencePattern.monthly:
          d = _addMonthsClamped(start, i);
      }
      keys.add(DateKey.fromDate(d));
    }

    return keys;
  }

  static DateTime _addMonthsClamped(DateTime source, int monthsToAdd) {
    final totalMonths = source.month - 1 + monthsToAdd;
    final y = source.year + (totalMonths ~/ 12);
    final m = (totalMonths % 12) + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final d = math.min(source.day, lastDay);
    return DateTime(y, m, d);
  }

  static bool _getBool(Object? settings, String key, bool defaultValue) {
    if (settings is! Map) return defaultValue;
    final value = settings[key];
    return value is bool ? value : defaultValue;
  }

  static int _getInt(Object? settings, String key, int defaultValue) {
    if (settings is! Map) return defaultValue;
    final value = settings[key];
    return value is int ? value : defaultValue;
  }

  static double _getDouble(Object? settings, String key, double defaultValue) {
    if (settings is! Map) return defaultValue;
    final value = settings[key];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return defaultValue;
  }

  static String _getString(Object? settings, String key, String defaultValue) {
    if (settings is! Map) return defaultValue;
    final value = settings[key];
    return value is String ? value : defaultValue;
  }

  static List<String>? _getStringList(Object? settings, String key) {
    if (settings is! Map) return null;
    final value = settings[key];
    if (value is! List) return null;
    return value.whereType<String>().toList();
  }

  static Color _getColor(Object? settings, String key, Color defaultValue) {
    if (settings is! Map) return defaultValue;
    final value = settings[key];
    if (value is! String) return defaultValue;
    if (!value.startsWith('#') || value.length != 7) return defaultValue;
    try {
      final hex = value.substring(1);
      final intValue = int.parse(hex, radix: 16);
      return Color(0xFF000000 | intValue);
    } catch (_) {
      return defaultValue;
    }
  }

  static int _sanitizeWeekStart(int value) {
    if (value == 0 || value == 1 || value == 6) return value;
    return 1;
  }

  static double _sanitizeTextScale(double value) {
    return value.clamp(1.0, 2.0);
  }

  static List<String> _sanitizePanelOrder(List<String>? raw) {
    if (raw == null) {
      return List<String>.from(_defaultPanelOrder);
    }
    const valid = {'date', 'totals', 'calendar'};
    final unique = <String>[];
    for (final id in raw) {
      if (valid.contains(id) && !unique.contains(id)) {
        unique.add(id);
      }
    }
    for (final fallback in _defaultPanelOrder) {
      if (!unique.contains(fallback)) {
        unique.add(fallback);
      }
    }
    return unique.take(_defaultPanelOrder.length).toList(growable: false);
  }

  static String colorToHex(Color color) {
    return '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Future<void> updateColors({
    Color? incomeLight,
    Color? incomeDark,
    Color? expenseLight,
    Color? expenseDark,
    Color? bothLight,
    Color? bothDark,
  }) async {
    if (incomeLight != null) incomeColorLight = incomeLight;
    if (incomeDark != null) incomeColorDark = incomeDark;
    if (expenseLight != null) expenseColorLight = expenseLight;
    if (expenseDark != null) expenseColorDark = expenseDark;
    if (bothLight != null) bothColorLight = bothLight;
    if (bothDark != null) bothColorDark = bothDark;
    await _save();
    notifyListeners();
  }

  Future<void> updateDisplaySettings({
    bool? showRunning,
    bool? showMonth,
    bool? showDayRunningBalanceOnHover,
    bool? minimizeToTray,
  }) async {
    if (showRunning != null) showRunningBalance = showRunning;
    if (showMonth != null) showMonthBalance = showMonth;
    if (showDayRunningBalanceOnHover != null) {
      this.showDayRunningBalanceOnHover = showDayRunningBalanceOnHover;
    }
    if (minimizeToTray != null) {
      this.minimizeToTray = minimizeToTray;
    }
    await _save();
    notifyListeners();
  }

  Future<void> updateWeekStartDay(int startDay) async {
    if (startDay < 0 || startDay > 6) return;
    weekStartDay = _sanitizeWeekStart(startDay);
    await _save();
    notifyListeners();
  }

  Future<void> updateAccessibilitySettings({
    bool? highContrast,
    double? textScale,
  }) async {
    if (highContrast != null) highContrastMode = highContrast;
    if (textScale != null) textScaleFactor = _sanitizeTextScale(textScale);
    await _save();
    notifyListeners();
  }

  Future<void> updateBudgetSettings({
    String? currency,
    int? startingBalance,
    int? monthlyBudget,
  }) async {
    if (currency != null && currency.trim().isNotEmpty) {
      currencySymbol = currency.trim();
    }
    if (startingBalance != null) {
      startingBalancePennies = startingBalance;
      _bumpMetricsRevision();
    }
    if (monthlyBudget != null) {
      monthlyBudgetPennies = math.max(0, monthlyBudget);
    }
    await _save();
    notifyListeners();
  }

  Future<void> updatePanelOrder(List<String> order) async {
    panelOrderIds = _sanitizePanelOrder(order);
    await _save();
    notifyListeners();
  }

  Future<void> resetColorsToDefaults() async {
    incomeColorLight = const Color(0xFF2E7D32);
    incomeColorDark = const Color(0xFF66BB6A);
    expenseColorLight = const Color(0xFFC62828);
    expenseColorDark = const Color(0xFFEF5350);
    bothColorLight = const Color(0xFFFFB74D);
    bothColorDark = const Color(0xFFFFB74D);
    await _save();
    notifyListeners();
  }

  Future<bool> createBackupSnapshot({String reason = 'manual'}) async {
    await _autoBackup(reason);
    return true;
  }

  Future<bool> restoreLatestBackup() async {
    if (_backups.isEmpty) return false;
    final latest = _backups.last;
    return importFromJsonText(latest.dataJson, createBackupFirst: false);
  }

  Future<bool> importFromJsonText(
    String jsonText, {
    bool createBackupFirst = true,
  }) async {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return false;

      if (createBackupFirst) {
        await _autoBackup('pre-import');
      }

      final map =
          decoded.map((k, v) => MapEntry(k.toString(), v))
              as Map<String, Object?>;
      final settings = map['settings'];

      final parsedIncome = _parseEntryMap(map['income']);
      final parsedExpenses = _parseEntryMap(map['expenses']);

      darkMode = _getBool(settings, 'dark_mode', darkMode);
      incomeColorLight = _getColor(
        settings,
        'income_color_light',
        incomeColorLight,
      );
      incomeColorDark = _getColor(
        settings,
        'income_color_dark',
        incomeColorDark,
      );
      expenseColorLight = _getColor(
        settings,
        'expense_color_light',
        expenseColorLight,
      );
      expenseColorDark = _getColor(
        settings,
        'expense_color_dark',
        expenseColorDark,
      );
      bothColorLight = _getColor(settings, 'both_color_light', bothColorLight);
      bothColorDark = _getColor(settings, 'both_color_dark', bothColorDark);
      showRunningBalance = _getBool(
        settings,
        'show_running_balance',
        showRunningBalance,
      );
      showMonthBalance = _getBool(
        settings,
        'show_month_balance',
        showMonthBalance,
      );
      showDayRunningBalanceOnHover = _getBool(
        settings,
        'show_day_running_balance_on_hover',
        showDayRunningBalanceOnHover,
      );
      minimizeToTray = _getBool(settings, 'minimize_to_tray', minimizeToTray);
      weekStartDay = _sanitizeWeekStart(
        _getInt(settings, 'week_start_day', weekStartDay),
      );

      highContrastMode = _getBool(
        settings,
        'high_contrast_mode',
        highContrastMode,
      );
      textScaleFactor = _sanitizeTextScale(
        _getDouble(settings, 'text_scale_factor', textScaleFactor),
      );
      currencySymbol = _getString(settings, 'currency_symbol', currencySymbol);
      startingBalancePennies = _getInt(
        settings,
        'starting_balance_pennies',
        startingBalancePennies,
      );
      monthlyBudgetPennies = math.max(
        0,
        _getInt(settings, 'monthly_budget_pennies', monthlyBudgetPennies),
      );
      panelOrderIds = _sanitizePanelOrder(
        _getStringList(settings, 'panel_order'),
      );

      _income
        ..clear()
        ..addAll(parsedIncome);
      _expenses
        ..clear()
        ..addAll(parsedExpenses);
      _bumpMetricsRevision();

      final parsedBackups = _parseBackups(settings);
      if (parsedBackups.isNotEmpty) {
        _backups
          ..clear()
          ..addAll(parsedBackups.take(20));
      }

      final saved = await _saveReturningSuccess();
      if (!saved) return false;

      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Color getIncomeColor(bool isDark) =>
      isDark ? incomeColorDark : incomeColorLight;
  Color getExpenseColor(bool isDark) =>
      isDark ? expenseColorDark : expenseColorLight;
  Color getBothColor(bool isDark) => isDark ? bothColorDark : bothColorLight;

  int getFirstWeekdayOffset(DateTime firstDayOfMonth) {
    final dtWeekday = firstDayOfMonth.weekday % 7;
    return (dtWeekday - weekStartDay + 7) % 7;
  }

  List<String> getDayLabels() {
    const allDays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return [
      ...allDays.sublist(weekStartDay),
      ...allDays.sublist(0, weekStartDay),
    ];
  }
}

class _MemoryPersistence implements BudgetPersistence {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String contents) async {
    _value = contents;
  }
}
