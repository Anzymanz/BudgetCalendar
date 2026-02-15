import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_calendar/state/budget_store.dart';

void main() {
  group('BudgetStore settings', () {
    test('default settings are loaded correctly', () {
      final store = BudgetStore.inMemory();

      expect(store.darkMode, false);
      expect(store.incomeColorLight, const Color(0xFF2E7D32));
      expect(store.incomeColorDark, const Color(0xFF66BB6A));
      expect(store.expenseColorLight, const Color(0xFFC62828));
      expect(store.expenseColorDark, const Color(0xFFEF5350));
      expect(store.bothColorLight, const Color(0xFF5C6F7D));
      expect(store.bothColorDark, const Color(0xFF8F9CA8));
      expect(store.showMonthBalance, true);
      expect(store.showRunningBalance, true);
      expect(store.showDayRunningBalanceOnHover, true);
      expect(store.weekStartDay, 1);
      expect(store.highContrastMode, false);
      expect(store.textScaleFactor, 1.0);
      expect(store.currencySymbol, '£');
      expect(store.startingBalancePennies, 0);
      expect(store.monthlyBudgetPennies, 0);
      expect(store.panelOrderIds, ['date', 'totals', 'calendar']);
    });

    test('toJson includes new settings keys', () {
      final store = BudgetStore.inMemory();
      final json = store.toJson();
      final settings = json['settings'] as Map<String, Object?>;

      expect(settings['high_contrast_mode'], false);
      expect(settings['text_scale_factor'], 1.0);
      expect(settings['show_day_running_balance_on_hover'], true);
      expect(settings['currency_symbol'], '£');
      expect(settings['starting_balance_pennies'], 0);
      expect(settings['monthly_budget_pennies'], 0);
      expect(settings['both_color_light'], '#5C6F7D');
      expect(settings['both_color_dark'], '#8F9CA8');
      expect(settings['panel_order'], ['date', 'totals', 'calendar']);
      expect(settings['backups'], isA<List>());
    });

    test('updateAccessibilitySettings clamps text scale', () async {
      final store = BudgetStore.inMemory();
      await store.updateAccessibilitySettings(
        highContrast: true,
        textScale: 5.0,
      );

      expect(store.highContrastMode, true);
      expect(store.textScaleFactor, 2.0);

      await store.updateAccessibilitySettings(textScale: 0.2);
      expect(store.textScaleFactor, 1.0);
    });

    test('updateBudgetSettings updates currency and budget fields', () async {
      final store = BudgetStore.inMemory();

      await store.updateBudgetSettings(
        currency: r'$',
        startingBalance: -2500,
        monthlyBudget: 125000,
      );

      expect(store.currencySymbol, r'$');
      expect(store.startingBalancePennies, -2500);
      expect(store.monthlyBudgetPennies, 125000);
    });

    test('updatePanelOrder sanitizes and persists panel order', () async {
      final store = BudgetStore.inMemory();
      await store.updatePanelOrder(['calendar', 'totals', 'calendar']);
      expect(store.panelOrderIds, ['calendar', 'totals', 'date']);
    });

    test('updateDisplaySettings toggles day hover running balance', () async {
      final store = BudgetStore.inMemory();
      await store.updateDisplaySettings(showDayRunningBalanceOnHover: false);
      expect(store.showDayRunningBalanceOnHover, false);
    });
  });

  group('Entries and recurrence', () {
    test('entry note is serialized and preserved', () async {
      final store = BudgetStore.inMemory();
      await store.addEntry(
        '2026-02-14',
        EntryType.expense,
        BudgetEntry(
          name: 'Groceries',
          amountPennies: 4500,
          note: 'Weekly shop',
        ),
      );

      final json = store.toJson();
      final expenses = json['expenses'] as Map<String, Object?>;
      final list = expenses['2026-02-14'] as List<dynamic>;
      final row = list.first as Map<String, dynamic>;
      expect(row['note'], 'Weekly shop');
    });

    test('addEntryWithRecurrence creates weekly series', () async {
      final store = BudgetStore.inMemory();
      await store.addEntryWithRecurrence(
        '2026-02-14',
        EntryType.income,
        BudgetEntry(name: 'Pay', amountPennies: 100000),
        RecurrencePattern.weekly,
        4,
      );

      expect(store.incomeForDay('2026-02-14').length, 1);
      expect(store.incomeForDay('2026-02-21').length, 1);
      expect(store.incomeForDay('2026-02-28').length, 1);
      expect(store.incomeForDay('2026-03-07').length, 1);
    });

    test('monthly recurrence clamps to end-of-month dates', () {
      final keys = BudgetStore.generateRecurringDateKeys(
        '2026-01-31',
        RecurrencePattern.monthly,
        3,
      );

      expect(keys[0], '2026-01-31');
      expect(keys[1], '2026-02-28');
      expect(keys[2], '2026-03-31');
    });
  });

  group('Failsafes and data management', () {
    test('importFromJsonText rejects invalid data', () async {
      final store = BudgetStore.inMemory();
      await store.addEntry(
        '2026-02-14',
        EntryType.income,
        BudgetEntry(name: 'Test', amountPennies: 1000),
      );

      final ok = await store.importFromJsonText('not-json');
      expect(ok, false);
      expect(store.incomeForDay('2026-02-14').length, 1);
    });

    test('importFromJsonText accepts valid data', () async {
      final store = BudgetStore.inMemory();
      final payload = jsonEncode({
        'income': {
          '2026-03-01': [
            {'name': 'Salary', 'amount': 1000.0, 'note': 'Main'},
          ],
        },
        'expenses': {},
        'settings': {
          'currency_symbol': '€',
          'high_contrast_mode': true,
          'text_scale_factor': 1.4,
          'starting_balance_pennies': 5000,
          'monthly_budget_pennies': 200000,
          'week_start_day': 0,
          'show_day_running_balance_on_hover': false,
          'both_color_light': '#112233',
          'both_color_dark': '#334455',
          'panel_order': ['calendar', 'date', 'totals'],
        },
      });

      final ok = await store.importFromJsonText(payload);
      expect(ok, true);
      expect(store.currencySymbol, '€');
      expect(store.highContrastMode, true);
      expect(store.textScaleFactor, 1.4);
      expect(store.startingBalancePennies, 5000);
      expect(store.monthlyBudgetPennies, 200000);
      expect(store.weekStartDay, 0);
      expect(store.showDayRunningBalanceOnHover, false);
      expect(store.bothColorLight, const Color(0xFF112233));
      expect(store.bothColorDark, const Color(0xFF334455));
      expect(store.panelOrderIds, ['calendar', 'date', 'totals']);
      expect(store.incomeForDay('2026-03-01').first.note, 'Main');
    });

    test('manual backup and restore roundtrip', () async {
      final store = BudgetStore.inMemory();
      await store.addEntry(
        '2026-02-14',
        EntryType.expense,
        BudgetEntry(name: 'A', amountPennies: 100),
      );

      final backupOk = await store.createBackupSnapshot();
      expect(backupOk, true);
      expect(store.backupCount, greaterThan(0));

      await store.importFromJsonText(
        jsonEncode({
          'income': {},
          'expenses': {},
          'settings': {'currency_symbol': r'$'},
        }),
      );

      expect(store.currencySymbol, r'$');

      final restored = await store.restoreLatestBackup();
      expect(restored, true);
      expect(store.expenseForDay('2026-02-14').length, 1);
    });
  });

  group('Color hex conversion', () {
    test('colorToHex produces expected uppercase #RRGGBB values', () {
      expect(BudgetStore.colorToHex(const Color(0xFF000000)), '#000000');
      expect(BudgetStore.colorToHex(const Color(0xFFFFFFFF)), '#FFFFFF');
      expect(BudgetStore.colorToHex(const Color(0xFF123456)), '#123456');
      expect(BudgetStore.colorToHex(const Color(0xFFABCDEF)), '#ABCDEF');
      expect(BudgetStore.colorToHex(const Color(0xFFabcdef)), '#ABCDEF');
    });
  });
}
