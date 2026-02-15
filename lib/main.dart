import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'state/budget_store.dart';
import 'util/date_key.dart';

String formatCurrency(BudgetStore store, int pennies) {
  final f = NumberFormat.currency(
    locale: 'en_GB',
    symbol: store.currencySymbol,
  );
  return f.format(pennies / 100);
}

const _windowWidthPrefKey = 'window_width';
const _windowHeightPrefKey = 'window_height';
const _uiTweaksPrefKey = 'ui_tweaks_v1';
const _uiTweaksDefaultPrefKey = 'ui_tweaks_default_v1';
const _defaultCompactMetricBaseWidth = 620.0;
const _windowKindTweaks = 'ui_tweaks';

Future<UiTweakConfig> _loadUiTweaksFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey(_uiTweaksPrefKey)) {
    return UiTweakConfig.fromJsonString(prefs.getString(_uiTweaksPrefKey));
  }
  return _loadUiTweaksDefaultFromPrefs();
}

Future<void> _saveUiTweaksToPrefs(UiTweakConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_uiTweaksPrefKey, config.toJsonString());
}

Future<UiTweakConfig> _loadUiTweaksDefaultFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return UiTweakConfig.fromJsonString(prefs.getString(_uiTweaksDefaultPrefKey));
}

Future<void> _saveUiTweaksDefaultToPrefs(UiTweakConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_uiTweaksDefaultPrefKey, config.toJsonString());
}

double _compactMetricWidthThreshold(
  double textScaleFactor, {
  required double baseWidth,
}) {
  final scale = textScaleFactor.clamp(1.0, 2.0);
  return baseWidth * scale;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) &&
      args.isNotEmpty &&
      args.first == 'multi_window') {
    final childController = await WindowController.fromCurrentEngine();
    final rawArgs = childController.arguments;
    Map<String, dynamic> parsedArgs = const <String, dynamic>{};
    if (rawArgs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map<String, dynamic>) {
          parsedArgs = decoded;
        }
      } catch (_) {}
    }
    if (parsedArgs['kind'] == _windowKindTweaks) {
      final initialTweaks = await _loadUiTweaksFromPrefs();
      final mainWindowId = parsedArgs['mainWindowId'] as String?;
      runApp(
        _UiTweaksWindowApp(
          initialTweaks: initialTweaks,
          mainWindowId: mainWindowId,
        ),
      );
      return;
    }
  }
  final tweakMode =
      args.contains('-tweak') ||
      args.contains('--tweak') ||
      args.contains('/tweak');
  final prefs = await SharedPreferences.getInstance();
  final initialTweaks = await _loadUiTweaksFromPrefs();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    final savedWidth = prefs.getDouble(_windowWidthPrefKey);
    final savedHeight = prefs.getDouble(_windowHeightPrefKey);
    await windowManager.ensureInitialized();
    final windowOptions = WindowOptions(
      size: Size(savedWidth ?? 770, savedHeight ?? 887),
      minimumSize: Size(420, 560),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  final store = await BudgetStore.load();
  runApp(
    BudgetCalendarApp(
      store: store,
      tweakModeEnabled: tweakMode,
      initialUiTweaks: initialTweaks,
    ),
  );
}

class BudgetCalendarApp extends StatelessWidget {
  const BudgetCalendarApp({
    super.key,
    required this.store,
    required this.tweakModeEnabled,
    required this.initialUiTweaks,
  });

  final BudgetStore store;
  final bool tweakModeEnabled;
  final UiTweakConfig initialUiTweaks;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        var light = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5C6166),
            surface: const Color(0xFFF4F4F4),
          ),
          scaffoldBackgroundColor: const Color(0xFFF4F4F4),
          useMaterial3: true,
        );

        var dark = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8B8D90),
            brightness: Brightness.dark,
            surface: const Color(0xFF181818),
          ).copyWith(surfaceContainerLow: const Color(0xFF1F1F1F)),
          scaffoldBackgroundColor: const Color(0xFF181818),
          useMaterial3: true,
        );

        if (store.highContrastMode) {
          light = light.copyWith(
            colorScheme: light.colorScheme.copyWith(
              surface: Colors.white,
              onSurface: Colors.black,
              primary: Colors.black,
              onPrimary: Colors.white,
              outline: Colors.black,
              surfaceContainerLow: Colors.white,
              surfaceContainerHighest: Colors.white,
            ),
          );
          dark = dark.copyWith(
            colorScheme: dark.colorScheme.copyWith(
              surface: Colors.black,
              onSurface: Colors.white,
              primary: Colors.white,
              onPrimary: Colors.black,
              outline: Colors.white,
              surfaceContainerLow: Colors.black,
              surfaceContainerHighest: Colors.black,
            ),
          );
        }

        light = light.copyWith(
          scaffoldBackgroundColor: light.colorScheme.surface,
          cardTheme: CardThemeData(
            color: light.colorScheme.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: store.highContrastMode
                    ? light.colorScheme.outline
                    : Colors.transparent,
                width: store.highContrastMode ? 2 : 0,
              ),
            ),
          ),
          dividerTheme: DividerThemeData(
            color: store.highContrastMode
                ? light.colorScheme.outline
                : light.colorScheme.outlineVariant,
            thickness: store.highContrastMode ? 2 : 1,
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return light.colorScheme.surface;
              }
              return light.colorScheme.onSurface;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return light.colorScheme.onSurface;
              }
              return light.colorScheme.surface;
            }),
            trackOutlineColor: WidgetStateProperty.all(
              light.colorScheme.outline,
            ),
            trackOutlineWidth: WidgetStateProperty.all(
              store.highContrastMode ? 2 : 1,
            ),
          ),
          sliderTheme: light.sliderTheme.copyWith(
            activeTrackColor: light.colorScheme.onSurface,
            inactiveTrackColor: store.highContrastMode
                ? light.colorScheme.outline
                : light.colorScheme.outlineVariant,
            thumbColor: light.colorScheme.onSurface,
            overlayColor: light.colorScheme.onSurface.withValues(alpha: 0.15),
            trackHeight: store.highContrastMode ? 5 : 4,
          ),
          listTileTheme: ListTileThemeData(
            iconColor: light.colorScheme.onSurface,
            textColor: light.colorScheme.onSurface,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: light.colorScheme.surface,
            foregroundColor: light.colorScheme.onSurface,
            surfaceTintColor: Colors.transparent,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: light.colorScheme.surface,
            titleTextStyle: TextStyle(
              color: light.colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            contentTextStyle: TextStyle(color: light.colorScheme.onSurface),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: store.highContrastMode
                    ? light.colorScheme.outline
                    : light.colorScheme.outlineVariant,
                width: store.highContrastMode ? 2 : 1,
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: store.highContrastMode
                    ? light.colorScheme.outline
                    : light.colorScheme.outlineVariant,
                width: store.highContrastMode ? 2 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: store.highContrastMode
                    ? light.colorScheme.outline
                    : light.colorScheme.outlineVariant,
                width: store.highContrastMode ? 2 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: light.colorScheme.primary,
                width: store.highContrastMode ? 3 : 2,
              ),
            ),
          ),
        );
        dark = dark.copyWith(
          scaffoldBackgroundColor: dark.colorScheme.surface,
          cardTheme: CardThemeData(
            color: dark.colorScheme.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: store.highContrastMode
                    ? dark.colorScheme.outline
                    : Colors.transparent,
                width: store.highContrastMode ? 2 : 0,
              ),
            ),
          ),
          dividerTheme: DividerThemeData(
            color: store.highContrastMode
                ? dark.colorScheme.outline
                : dark.colorScheme.outlineVariant,
            thickness: store.highContrastMode ? 2 : 1,
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return dark.colorScheme.surface;
              }
              return dark.colorScheme.onSurface;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return dark.colorScheme.onSurface;
              }
              return dark.colorScheme.surface;
            }),
            trackOutlineColor: WidgetStateProperty.all(
              dark.colorScheme.outline,
            ),
            trackOutlineWidth: WidgetStateProperty.all(
              store.highContrastMode ? 2 : 1,
            ),
          ),
          sliderTheme: dark.sliderTheme.copyWith(
            activeTrackColor: dark.colorScheme.onSurface,
            inactiveTrackColor: store.highContrastMode
                ? dark.colorScheme.outline
                : dark.colorScheme.outlineVariant,
            thumbColor: dark.colorScheme.onSurface,
            overlayColor: dark.colorScheme.onSurface.withValues(alpha: 0.15),
            trackHeight: store.highContrastMode ? 5 : 4,
          ),
          listTileTheme: ListTileThemeData(
            iconColor: dark.colorScheme.onSurface,
            textColor: dark.colorScheme.onSurface,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: dark.colorScheme.surface,
            foregroundColor: dark.colorScheme.onSurface,
            surfaceTintColor: Colors.transparent,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: dark.colorScheme.surface,
            titleTextStyle: TextStyle(
              color: dark.colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            contentTextStyle: TextStyle(color: dark.colorScheme.onSurface),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: store.highContrastMode
                    ? dark.colorScheme.outline
                    : dark.colorScheme.outlineVariant,
                width: store.highContrastMode ? 2 : 1,
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: store.highContrastMode
                    ? dark.colorScheme.outline
                    : dark.colorScheme.outlineVariant,
                width: store.highContrastMode ? 2 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: store.highContrastMode
                    ? dark.colorScheme.outline
                    : dark.colorScheme.outlineVariant,
                width: store.highContrastMode ? 2 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: dark.colorScheme.primary,
                width: store.highContrastMode ? 3 : 2,
              ),
            ),
          ),
        );

        light = light.copyWith(
          tooltipTheme: TooltipThemeData(
            waitDuration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: light.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: light.colorScheme.outline),
            ),
            textStyle: TextStyle(color: light.colorScheme.onSurface),
          ),
        );
        dark = dark.copyWith(
          tooltipTheme: TooltipThemeData(
            waitDuration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: dark.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: dark.colorScheme.outline),
            ),
            textStyle: TextStyle(color: dark.colorScheme.onSurface),
          ),
        );

        return MaterialApp(
          title: 'Budget Calendar',
          theme: light,
          darkTheme: dark,
          themeMode: store.darkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(store.textScaleFactor),
                highContrast: store.highContrastMode,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: BudgetCalendarHome(
            store: store,
            tweakModeEnabled: tweakModeEnabled,
            initialUiTweaks: initialUiTweaks,
          ),
        );
      },
    );
  }
}

class _UiTweaksWindowApp extends StatelessWidget {
  const _UiTweaksWindowApp({
    required this.initialTweaks,
    required this.mainWindowId,
  });

  final UiTweakConfig initialTweaks;
  final String? mainWindowId;

  Future<void> _applyAndNotify(UiTweakConfig config) async {
    await _saveUiTweaksToPrefs(config);
    if (mainWindowId == null) return;
    try {
      final mainWindow = WindowController.fromWindowId(mainWindowId!);
      await mainWindow.invokeMethod('uiTweaksUpdated', config.toJsonString());
    } catch (_) {}
  }

  Future<void> _saveAsDefaultAndNotify(UiTweakConfig config) async {
    await _saveUiTweaksDefaultToPrefs(config);
    if (mainWindowId == null) return;
    try {
      final mainWindow = WindowController.fromWindowId(mainWindowId!);
      await mainWindow.invokeMethod(
        'uiTweaksDefaultUpdated',
        config.toJsonString(),
      );
    } catch (_) {}
  }

  Future<UiTweakConfig> _resetToDefaultAndNotify() async {
    final defaults = await _loadUiTweaksDefaultFromPrefs();
    await _applyAndNotify(defaults);
    return defaults;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Budget Calendar - UI Tweak Lab',
      theme: ThemeData(useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('UI Tweak Lab'),
          actions: [
            IconButton(
              tooltip: 'Close',
              onPressed: () async {
                try {
                  final current = await WindowController.fromCurrentEngine();
                  await current.hide();
                } catch (_) {}
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: _UiTweaksDialog(
          initial: initialTweaks,
          onApply: _applyAndNotify,
          onApplyAndReload: _applyAndNotify,
          onSaveCurrentAsDefault: _saveAsDefaultAndNotify,
          onResetToDefaults: _resetToDefaultAndNotify,
        ),
      ),
    );
  }
}

class BudgetCalendarHome extends StatefulWidget {
  const BudgetCalendarHome({
    super.key,
    required this.store,
    required this.tweakModeEnabled,
    required this.initialUiTweaks,
  });

  final BudgetStore store;
  final bool tweakModeEnabled;
  final UiTweakConfig initialUiTweaks;

  @override
  State<BudgetCalendarHome> createState() => _BudgetCalendarHomeState();
}

class _MonthSummaryCacheEntry {
  const _MonthSummaryCacheEntry({
    required this.metricsRevision,
    required this.monthIncomePennies,
    required this.monthExpensePennies,
    required this.runningBalancePennies,
  });

  final int metricsRevision;
  final int monthIncomePennies;
  final int monthExpensePennies;
  final int runningBalancePennies;
}

class UiTweakConfig {
  const UiTweakConfig({
    required this.compactMetricBaseWidth,
    required this.metricCompactMinCardWidth,
    required this.metricExpandedMinCardWidth,
    required this.dayNumberBoxWidthBase,
    required this.dayNumberBoxWidthBoost,
    required this.dayNumberBoxHeightBase,
    required this.dayNumberBoxHeightBoost,
    required this.dayNumberBaseFont,
    required this.dayNumberFontBoost,
    required this.badgeBaseSmallFont,
    required this.badgeBaseLargeFont,
    required this.badgeFontBoost,
    required this.amountBaseSmallFont,
    required this.amountBaseLargeFont,
    required this.amountFontBoost,
    required this.showEntryBadgeMinCell,
    required this.showDayBalanceMinCell,
  });

  static const defaults = UiTweakConfig(
    compactMetricBaseWidth: _defaultCompactMetricBaseWidth,
    metricCompactMinCardWidth: 140,
    metricExpandedMinCardWidth: 165,
    dayNumberBoxWidthBase: 0.58,
    dayNumberBoxWidthBoost: 0.08,
    dayNumberBoxHeightBase: 0.42,
    dayNumberBoxHeightBoost: 0.08,
    dayNumberBaseFont: 19,
    dayNumberFontBoost: 3,
    badgeBaseSmallFont: 9,
    badgeBaseLargeFont: 10,
    badgeFontBoost: 0.35,
    amountBaseSmallFont: 12,
    amountBaseLargeFont: 13,
    amountFontBoost: 0.45,
    showEntryBadgeMinCell: 46,
    showDayBalanceMinCell: 58,
  );

  final double compactMetricBaseWidth;
  final double metricCompactMinCardWidth;
  final double metricExpandedMinCardWidth;
  final double dayNumberBoxWidthBase;
  final double dayNumberBoxWidthBoost;
  final double dayNumberBoxHeightBase;
  final double dayNumberBoxHeightBoost;
  final double dayNumberBaseFont;
  final double dayNumberFontBoost;
  final double badgeBaseSmallFont;
  final double badgeBaseLargeFont;
  final double badgeFontBoost;
  final double amountBaseSmallFont;
  final double amountBaseLargeFont;
  final double amountFontBoost;
  final double showEntryBadgeMinCell;
  final double showDayBalanceMinCell;

  UiTweakConfig copyWith({
    double? compactMetricBaseWidth,
    double? metricCompactMinCardWidth,
    double? metricExpandedMinCardWidth,
    double? dayNumberBoxWidthBase,
    double? dayNumberBoxWidthBoost,
    double? dayNumberBoxHeightBase,
    double? dayNumberBoxHeightBoost,
    double? dayNumberBaseFont,
    double? dayNumberFontBoost,
    double? badgeBaseSmallFont,
    double? badgeBaseLargeFont,
    double? badgeFontBoost,
    double? amountBaseSmallFont,
    double? amountBaseLargeFont,
    double? amountFontBoost,
    double? showEntryBadgeMinCell,
    double? showDayBalanceMinCell,
  }) {
    return UiTweakConfig(
      compactMetricBaseWidth:
          compactMetricBaseWidth ?? this.compactMetricBaseWidth,
      metricCompactMinCardWidth:
          metricCompactMinCardWidth ?? this.metricCompactMinCardWidth,
      metricExpandedMinCardWidth:
          metricExpandedMinCardWidth ?? this.metricExpandedMinCardWidth,
      dayNumberBoxWidthBase:
          dayNumberBoxWidthBase ?? this.dayNumberBoxWidthBase,
      dayNumberBoxWidthBoost:
          dayNumberBoxWidthBoost ?? this.dayNumberBoxWidthBoost,
      dayNumberBoxHeightBase:
          dayNumberBoxHeightBase ?? this.dayNumberBoxHeightBase,
      dayNumberBoxHeightBoost:
          dayNumberBoxHeightBoost ?? this.dayNumberBoxHeightBoost,
      dayNumberBaseFont: dayNumberBaseFont ?? this.dayNumberBaseFont,
      dayNumberFontBoost: dayNumberFontBoost ?? this.dayNumberFontBoost,
      badgeBaseSmallFont: badgeBaseSmallFont ?? this.badgeBaseSmallFont,
      badgeBaseLargeFont: badgeBaseLargeFont ?? this.badgeBaseLargeFont,
      badgeFontBoost: badgeFontBoost ?? this.badgeFontBoost,
      amountBaseSmallFont: amountBaseSmallFont ?? this.amountBaseSmallFont,
      amountBaseLargeFont: amountBaseLargeFont ?? this.amountBaseLargeFont,
      amountFontBoost: amountFontBoost ?? this.amountFontBoost,
      showEntryBadgeMinCell:
          showEntryBadgeMinCell ?? this.showEntryBadgeMinCell,
      showDayBalanceMinCell:
          showDayBalanceMinCell ?? this.showDayBalanceMinCell,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'compact_metric_base_width': compactMetricBaseWidth,
      'metric_compact_min_card_width': metricCompactMinCardWidth,
      'metric_expanded_min_card_width': metricExpandedMinCardWidth,
      'day_number_box_width_base': dayNumberBoxWidthBase,
      'day_number_box_width_boost': dayNumberBoxWidthBoost,
      'day_number_box_height_base': dayNumberBoxHeightBase,
      'day_number_box_height_boost': dayNumberBoxHeightBoost,
      'day_number_base_font': dayNumberBaseFont,
      'day_number_font_boost': dayNumberFontBoost,
      'badge_base_small_font': badgeBaseSmallFont,
      'badge_base_large_font': badgeBaseLargeFont,
      'badge_font_boost': badgeFontBoost,
      'amount_base_small_font': amountBaseSmallFont,
      'amount_base_large_font': amountBaseLargeFont,
      'amount_font_boost': amountFontBoost,
      'show_entry_badge_min_cell': showEntryBadgeMinCell,
      'show_day_balance_min_cell': showDayBalanceMinCell,
    };
  }

  String toJsonString() => jsonEncode(toMap());

  static UiTweakConfig fromJsonString(String? jsonText) {
    if (jsonText == null || jsonText.trim().isEmpty) {
      return UiTweakConfig.defaults;
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        return UiTweakConfig.defaults;
      }
      double readNum(String key, double fallback) {
        final value = decoded[key];
        if (value is num) return value.toDouble();
        return fallback;
      }

      final d = UiTweakConfig.defaults;
      return UiTweakConfig(
        compactMetricBaseWidth: readNum(
          'compact_metric_base_width',
          d.compactMetricBaseWidth,
        ),
        metricCompactMinCardWidth: readNum(
          'metric_compact_min_card_width',
          d.metricCompactMinCardWidth,
        ),
        metricExpandedMinCardWidth: readNum(
          'metric_expanded_min_card_width',
          d.metricExpandedMinCardWidth,
        ),
        dayNumberBoxWidthBase: readNum(
          'day_number_box_width_base',
          d.dayNumberBoxWidthBase,
        ),
        dayNumberBoxWidthBoost: readNum(
          'day_number_box_width_boost',
          d.dayNumberBoxWidthBoost,
        ),
        dayNumberBoxHeightBase: readNum(
          'day_number_box_height_base',
          d.dayNumberBoxHeightBase,
        ),
        dayNumberBoxHeightBoost: readNum(
          'day_number_box_height_boost',
          d.dayNumberBoxHeightBoost,
        ),
        dayNumberBaseFont: readNum('day_number_base_font', d.dayNumberBaseFont),
        dayNumberFontBoost: readNum(
          'day_number_font_boost',
          d.dayNumberFontBoost,
        ),
        badgeBaseSmallFont: readNum(
          'badge_base_small_font',
          d.badgeBaseSmallFont,
        ),
        badgeBaseLargeFont: readNum(
          'badge_base_large_font',
          d.badgeBaseLargeFont,
        ),
        badgeFontBoost: readNum('badge_font_boost', d.badgeFontBoost),
        amountBaseSmallFont: readNum(
          'amount_base_small_font',
          d.amountBaseSmallFont,
        ),
        amountBaseLargeFont: readNum(
          'amount_base_large_font',
          d.amountBaseLargeFont,
        ),
        amountFontBoost: readNum('amount_font_boost', d.amountFontBoost),
        showEntryBadgeMinCell: readNum(
          'show_entry_badge_min_cell',
          d.showEntryBadgeMinCell,
        ),
        showDayBalanceMinCell: readNum(
          'show_day_balance_min_cell',
          d.showDayBalanceMinCell,
        ),
      );
    } catch (_) {
      return UiTweakConfig.defaults;
    }
  }
}

class _BudgetCalendarHomeState extends State<BudgetCalendarHome>
    with WindowListener, TrayListener {
  late DateTime _focusedMonth;
  late PageController _pageController;
  late DateTime _referenceMonth; // Fixed reference for page calculations
  final List<_PanelType> _panelOrder = [
    _PanelType.date,
    _PanelType.totals,
    _PanelType.calendar,
  ];

  static const int _initialPageIndex = 1000;
  static const Duration _pageAnimDuration = Duration(milliseconds: 240);
  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool _windowResizeScheduled = false;
  bool _windowSizingInitialized = false;
  bool _isPageInMotion = false;
  Timer? _windowPersistDebounce;
  String _lastResizeLayoutKey = '';
  bool _trayInitialized = false;
  bool _lastMinimizeToTray = false;
  int _lastMetricsRevision = 0;
  int _uiTweaksRevision = 0;
  late UiTweakConfig _uiTweaks;
  String? _mainWindowId;
  WindowController? _tweaksWindowController;
  final Map<String, _MonthSummaryCacheEntry> _monthSummaryCache = {};

  static const String _trayMenuShowKey = 'show_window';
  static const String _trayMenuExitKey = 'exit_app';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _referenceMonth = _focusedMonth; // Store the initial month as reference
    _pageController = PageController(initialPage: _initialPageIndex);
    _loadPanelOrderFromStore();
    _lastResizeLayoutKey = _resizeLayoutKey();
    _lastMinimizeToTray = widget.store.minimizeToTray;
    _lastMetricsRevision = widget.store.metricsRevision;
    _uiTweaks = widget.initialUiTweaks;
    widget.store.addListener(_onStoreChanged);
    if (_isWindowsDesktop) {
      _initWindowSizing();
      _initMultiWindowBridge();
      if (_lastMinimizeToTray) {
        unawaited(_initTray());
      }
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    if (_isWindowsDesktop) {
      windowManager.removeListener(this);
      if (_trayInitialized) {
        trayManager.removeListener(this);
        unawaited(trayManager.destroy());
      }
    }
    _windowPersistDebounce?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (_lastMetricsRevision != widget.store.metricsRevision) {
      _lastMetricsRevision = widget.store.metricsRevision;
      _monthSummaryCache.clear();
    }
    if (!_isWindowsDesktop) return;
    if (_lastMinimizeToTray != widget.store.minimizeToTray) {
      _lastMinimizeToTray = widget.store.minimizeToTray;
      unawaited(_syncTrayPreference());
    }
    final key = _resizeLayoutKey();
    if (key == _lastResizeLayoutKey) {
      return;
    }
    _lastResizeLayoutKey = key;
    _scheduleWindowResizeToContent();
  }

  Future<void> _initTray() async {
    if (!_isWindowsDesktop || _trayInitialized) return;
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('BudgetCalendar');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _trayMenuShowKey, label: 'Show BudgetCalendar'),
          MenuItem.separator(),
          MenuItem(key: _trayMenuExitKey, label: 'Exit'),
        ],
      ),
    );
    _trayInitialized = true;
  }

  Future<void> _syncTrayPreference() async {
    if (!_isWindowsDesktop) return;
    if (widget.store.minimizeToTray) {
      await _initTray();
      return;
    }
    if (!_trayInitialized) return;
    trayManager.removeListener(this);
    _trayInitialized = false;
    await trayManager.destroy();
    await windowManager.setSkipTaskbar(false);
  }

  Future<void> _minimizeToTray() async {
    await _initTray();
    // If Windows has already minimized the window, restore first so hide()
    // transitions to a true hidden state and clears the taskbar button.
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> _restoreFromTray() async {
    await windowManager.setSkipTaskbar(false);
    final isVisible = await windowManager.isVisible();
    if (!isVisible) {
      await windowManager.show();
    }
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.focus();
  }

  Future<void> _exitFromTray() async {
    if (_trayInitialized) {
      trayManager.removeListener(this);
      _trayInitialized = false;
      await trayManager.destroy();
    }
    await windowManager.setSkipTaskbar(false);
    await windowManager.close();
  }

  void _handleMinimizePressed() {
    if (_isWindowsDesktop && widget.store.minimizeToTray) {
      unawaited(_minimizeToTray());
      return;
    }
    unawaited(windowManager.minimize());
  }

  @override
  void onWindowMinimize() {
    if (_isWindowsDesktop && widget.store.minimizeToTray) {
      unawaited(_minimizeToTray());
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_restoreFromTray());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == _trayMenuShowKey) {
      unawaited(_restoreFromTray());
      return;
    }
    if (menuItem.key == _trayMenuExitKey) {
      unawaited(_exitFromTray());
    }
  }

  String _resizeLayoutKey() {
    final s = widget.store;
    return [
      s.textScaleFactor.toStringAsFixed(2),
      s.showMonthBalance.toString(),
      s.showRunningBalance.toString(),
      (s.monthlyBudgetPennies > 0).toString(),
    ].join('|');
  }

  Future<void> _initWindowSizing() async {
    windowManager.addListener(this);
    _windowSizingInitialized = true;
    final prefs = await SharedPreferences.getInstance();
    final hasSavedSize =
        prefs.containsKey(_windowWidthPrefKey) &&
        prefs.containsKey(_windowHeightPrefKey);
    if (!hasSavedSize) {
      _scheduleWindowResizeToContent();
    }
  }

  @override
  void onWindowResize() {
    _windowPersistDebounce?.cancel();
    _windowPersistDebounce = Timer(const Duration(milliseconds: 220), () {
      _persistCurrentWindowSize();
    });
  }

  Future<void> _persistCurrentWindowSize() async {
    if (!_isWindowsDesktop) return;
    final size = await windowManager.getSize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_windowWidthPrefKey, size.width);
    await prefs.setDouble(_windowHeightPrefKey, size.height);
  }

  void _scheduleWindowResizeToContent() {
    if (!_windowSizingInitialized || _windowResizeScheduled || !mounted) {
      return;
    }
    _windowResizeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _windowResizeScheduled = false;
      if (!mounted) return;
      await _resizeWindowToContent();
    });
  }

  Future<void> _resizeWindowToContent() async {
    if (!_isWindowsDesktop) return;
    final currentSize = await windowManager.getSize();
    final targetHeight = _recommendedWindowHeight(currentSize.width);
    if ((targetHeight - currentSize.height).abs() < 1) return;
    await windowManager.setSize(
      Size(currentSize.width, targetHeight),
      animate: false,
    );
    await _persistCurrentWindowSize();
  }

  double _recommendedWindowHeight(double windowWidth) {
    final hideMetricTitles =
        windowWidth <
        _compactMetricWidthThreshold(
          widget.store.textScaleFactor,
          baseWidth: _uiTweaks.compactMetricBaseWidth,
        );
    final textScale = widget.store.textScaleFactor;
    const metricSpacing = 10.0;

    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final firstWeekday = widget.store.getFirstWeekdayOffset(first);
    final daysInMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    ).day;
    final rowCount = ((firstWeekday + daysInMonth + 6) ~/ 7);

    final showAnyBalance =
        widget.store.showMonthBalance || widget.store.showRunningBalance;
    final cardCount = showAnyBalance
        ? 2 +
              (widget.store.showMonthBalance ? 1 : 0) +
              (widget.store.showRunningBalance ? 1 : 0) +
              (widget.store.monthlyBudgetPennies > 0 ? 1 : 0)
        : 0;
    final availableMetricsWidth = (windowWidth - 24).clamp(
      0.0,
      double.infinity,
    );
    final minMetricCardWidth =
        (hideMetricTitles
            ? _uiTweaks.metricCompactMinCardWidth
            : _uiTweaks.metricExpandedMinCardWidth) *
        textScale;
    final metricColumns = cardCount == 0
        ? 1
        : ((availableMetricsWidth + metricSpacing) ~/
                  (minMetricCardWidth + metricSpacing))
              .clamp(1, cardCount);
    final metricRows = showAnyBalance
        ? ((cardCount + metricColumns - 1) ~/ metricColumns)
        : 1;

    final topBarHeight = _isWindowsDesktop ? 46.0 : 56.0;
    final monthHeaderHeight = 52.0 * textScale;
    final metricCardHeight = (hideMetricTitles ? 56.0 : 82.0) * textScale;
    final totalsHeight =
        24 +
        (metricRows * metricCardHeight) +
        (metricSpacing * (metricRows - 1));
    final calendarHeight =
        24 +
        (30 * textScale) +
        10 +
        (rowCount * ((hideMetricTitles ? 64.0 : 72.0) * textScale)) +
        (8 * (rowCount - 1));
    final contentHeight =
        topBarHeight +
        6 +
        monthHeaderHeight +
        10 +
        totalsHeight +
        10 +
        calendarHeight +
        12;

    return contentHeight.clamp(560.0, 2200.0);
  }

  int _visibleMetricCardCount(BudgetStore store) {
    final showAnyBalance = store.showMonthBalance || store.showRunningBalance;
    if (!showAnyBalance) return 0;
    var count = 2; // income + expenses
    if (store.showMonthBalance) count += 1;
    if (store.showRunningBalance) count += 1;
    if (store.monthlyBudgetPennies > 0) count += 1;
    return count;
  }

  bool _shouldPreferExpandedMetricCards({
    required BudgetStore store,
    required double contentWidth,
    required double contentHeight,
  }) {
    final cardCount = _visibleMetricCardCount(store);
    if (cardCount == 0) return false;

    final compactThreshold = _compactMetricWidthThreshold(
      store.textScaleFactor,
      baseWidth: _uiTweaks.compactMetricBaseWidth,
    );
    final widthWantsCompact = contentWidth < compactThreshold;
    if (!widthWantsCompact) return true;

    final textScale = store.textScaleFactor;
    const metricSpacing = 10.0;
    final availableMetricsWidth = (contentWidth - 24).clamp(
      0.0,
      double.infinity,
    );
    final compactMinWidth = _uiTweaks.metricCompactMinCardWidth * textScale;
    final expandedMinWidth = _uiTweaks.metricExpandedMinCardWidth * textScale;

    final compactColumns =
        ((availableMetricsWidth + metricSpacing) ~/
                (compactMinWidth + metricSpacing))
            .clamp(1, cardCount);
    final expandedColumns =
        ((availableMetricsWidth + metricSpacing) ~/
                (expandedMinWidth + metricSpacing))
            .clamp(1, cardCount);

    final compactRows = (cardCount + compactColumns - 1) ~/ compactColumns;
    final expandedRows = (cardCount + expandedColumns - 1) ~/ expandedColumns;

    final compactTotalsHeight =
        24 +
        (compactRows * (56.0 * textScale)) +
        (metricSpacing * (compactRows - 1));
    final expandedTotalsHeight =
        24 +
        (expandedRows * (82.0 * textScale)) +
        (metricSpacing * (expandedRows - 1));
    final extraNeededForExpanded = expandedTotalsHeight - compactTotalsHeight;
    if (extraNeededForExpanded <= 0) return true;

    // Keep compact-mode decisions month-independent to avoid mode flips when
    // switching between 5-row and 6-row calendar months.
    const rowCount = 6;
    const panelGap = 10.0;
    const panelPadding = 18.0; // from _buildMonthView outer padding
    final monthHeaderHeight = 52.0 * textScale;
    const daySpacing = 8.0;
    final panelInnerWidth = (contentWidth - 24).clamp(0.0, double.infinity);
    final estimatedGridHostWidth = (panelInnerWidth - 24).clamp(
      0.0,
      double.infinity,
    );
    final widthLimitedDayCell =
        ((estimatedGridHostWidth - (daySpacing * 6)) / 7).clamp(
          24.0 * textScale,
          76.0 * textScale,
        );
    final calendarMinComfortHeight =
        24 +
        (28.0 * textScale) +
        10 +
        (rowCount * widthLimitedDayCell) +
        (daySpacing * (rowCount - 1));

    final panelsHeightBudget = (contentHeight - panelPadding).clamp(
      0.0,
      double.infinity,
    );
    final compactCalendarHeight =
        panelsHeightBudget -
        monthHeaderHeight -
        (panelGap * 2) -
        compactTotalsHeight;
    final spareCalendarHeight =
        compactCalendarHeight - calendarMinComfortHeight;

    // On narrow windows we keep full cards longer to avoid abrupt mode flips
    // that can leave noticeable dead vertical space.
    final narrowWidthFactor =
        ((compactThreshold - contentWidth) / compactThreshold).clamp(0.0, 1.0);
    final verticalGrace = (10.0 + (36.0 * narrowWidthFactor)) * textScale;

    return spareCalendarHeight >= (extraNeededForExpanded - verticalGrace);
  }

  DateTime _monthForPageIndex(int pageIndex) {
    final offset = pageIndex - _initialPageIndex;
    return DateTime(_referenceMonth.year, _referenceMonth.month + offset, 1);
  }

  void _goToPreviousMonth() {
    _pageController.previousPage(
      duration: _pageAnimDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _goToNextMonth() {
    _pageController.nextPage(
      duration: _pageAnimDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToMonth(DateTime month) {
    final targetMonth = DateTime(month.year, month.month, 1);
    final monthsDiff =
        (targetMonth.year - _referenceMonth.year) * 12 +
        (targetMonth.month - _referenceMonth.month);
    final targetPage = _initialPageIndex + monthsDiff;

    _pageController.animateToPage(
      targetPage,
      duration: _pageAnimDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Detect if we should enable swipe (mobile platforms)
    final enableSwipe =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;

    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        return Scaffold(
          appBar: _buildTopBar(context),
          body: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification && !_isPageInMotion) {
                setState(() {
                  _isPageInMotion = true;
                });
              } else if (notification is ScrollEndNotification &&
                  _isPageInMotion) {
                setState(() {
                  _isPageInMotion = false;
                });
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              physics: enableSwipe
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                // Keep this update non-reactive to avoid an extra full rebuild
                // right after page animations settle.
                _focusedMonth = _monthForPageIndex(index);
              },
              itemBuilder: (context, pageIndex) {
                final month = _monthForPageIndex(pageIndex);
                return _buildMonthView(month, isPageInMotion: _isPageInMotion);
              },
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildTopBar(BuildContext context) {
    if (!_isWindowsDesktop) {
      return AppBar(
        actions: [
          if (widget.tweakModeEnabled)
            Tooltip(
              message: 'UI Tweak Lab',
              child: IconButton(
                onPressed: () => _openUiTweaksDialog(context),
                icon: const Icon(Icons.tune),
              ),
            ),
          Tooltip(
            message: 'Settings',
            child: IconButton(
              onPressed: () => _openSettingsDialog(context, widget.store),
              icon: const Icon(Icons.settings),
            ),
          ),
          Tooltip(
            message: widget.store.darkMode
                ? 'Disable dark mode'
                : 'Enable dark mode',
            child: IconButton(
              onPressed: widget.store.toggleDarkMode,
              icon: Icon(
                widget.store.darkMode
                    ? Icons.lightbulb
                    : Icons.lightbulb_outline,
              ),
            ),
          ),
        ],
      );
    }

    return PreferredSize(
      preferredSize: const Size.fromHeight(46),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 46,
          color: Theme.of(context).appBarTheme.backgroundColor,
          child: Row(
            children: [
              Expanded(
                child: DragToMoveArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Budget Calendar',
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Settings',
                child: IconButton(
                  onPressed: () => _openSettingsDialog(context, widget.store),
                  icon: const Icon(Icons.settings),
                ),
              ),
              if (widget.tweakModeEnabled)
                Tooltip(
                  message: 'UI Tweak Lab',
                  child: IconButton(
                    onPressed: () => _openUiTweaksDialog(context),
                    icon: const Icon(Icons.tune),
                  ),
                ),
              Tooltip(
                message: widget.store.darkMode
                    ? 'Disable dark mode'
                    : 'Enable dark mode',
                child: IconButton(
                  onPressed: widget.store.toggleDarkMode,
                  icon: Icon(
                    widget.store.darkMode
                        ? Icons.lightbulb
                        : Icons.lightbulb_outline,
                  ),
                ),
              ),
              Tooltip(
                message: 'Minimize',
                child: IconButton(
                  onPressed: _handleMinimizePressed,
                  icon: const Icon(Icons.remove),
                ),
              ),
              Tooltip(
                message: 'Close',
                child: IconButton(
                  onPressed: () => windowManager.close(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthView(DateTime month, {required bool isPageInMotion}) {
    final store = widget.store;
    final monthSummary = _getMonthSummary(store, month);
    final monthIncome = monthSummary.monthIncomePennies;
    final monthExpenses = monthSummary.monthExpensePennies;
    final monthBalance = monthIncome - monthExpenses;
    final runningBalance = monthSummary.runningBalancePennies;

    return LayoutBuilder(
      builder: (context, constraints) {
        final preferExpandedMetrics = _shouldPreferExpandedMetricCards(
          store: store,
          contentWidth: constraints.maxWidth,
          contentHeight: constraints.maxHeight,
        );
        final orderedPanels = <Widget>[];
        for (var i = 0; i < _panelOrder.length; i++) {
          final type = _panelOrder[i];
          if (i > 0) {
            orderedPanels.add(const SizedBox(height: 10));
          }

          if (type == _PanelType.date) {
            orderedPanels.add(
              _buildDraggablePanelSlot(
                type: _PanelType.date,
                child: _MonthHeader(
                  focusedMonth: month,
                  onPrev: _goToPreviousMonth,
                  onNext: _goToNextMonth,
                  onMonthSelected: _jumpToMonth,
                ),
              ),
            );
          } else if (type == _PanelType.totals) {
            orderedPanels.add(
              _buildDraggablePanelSlot(
                type: _PanelType.totals,
                child: _TotalsPanel(
                  store: store,
                  uiTweaks: _uiTweaks,
                  monthIncomePennies: monthIncome,
                  monthExpensePennies: monthExpenses,
                  monthBalancePennies: monthBalance,
                  runningBalancePennies: runningBalance,
                  preferExpandedMetrics: preferExpandedMetrics,
                ),
              ),
            );
          } else {
            orderedPanels.add(
              Expanded(
                child: _buildCalendarPanel(
                  context: context,
                  store: store,
                  month: month,
                  uiTweaks: _uiTweaks,
                  enableDragDrop: true,
                  enableHoverTooltips: !isPageInMotion,
                ),
              ),
            );
          }
        }

        return KeyedSubtree(
          key: ValueKey<String>(
            '${month.year}-${month.month}-$_uiTweaksRevision',
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(children: orderedPanels),
          ),
        );
      },
    );
  }

  _MonthSummaryCacheEntry _getMonthSummary(BudgetStore store, DateTime month) {
    final monthKey = '${month.year}-${month.month}';
    final cached = _monthSummaryCache[monthKey];
    if (cached != null && cached.metricsRevision == store.metricsRevision) {
      return cached;
    }
    final monthIncome = store.sumMonthIncomePennies(month);
    final monthExpenses = store.sumMonthExpensePennies(month);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final runningBalance = store.runningBalancePennies(monthEnd);
    final entry = _MonthSummaryCacheEntry(
      metricsRevision: store.metricsRevision,
      monthIncomePennies: monthIncome,
      monthExpensePennies: monthExpenses,
      runningBalancePennies: runningBalance,
    );
    _monthSummaryCache[monthKey] = entry;
    return entry;
  }

  Future<void> _openDayDialog(
    BuildContext context,
    BudgetStore store,
    DateTime day,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return _DayEntriesDialog(store: store, day: day);
      },
    );
  }

  Future<void> _openSettingsDialog(
    BuildContext context,
    BudgetStore store,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _SettingsDialog(
        store: store,
        showTweakControls: widget.tweakModeEnabled,
        onOpenUiTweaks: widget.tweakModeEnabled
            ? () => _openUiTweaksDialog(context)
            : null,
      ),
    );
  }

  Future<void> _openUiTweaksDialog(BuildContext context) async {
    if (_isWindowsDesktop) {
      try {
        final controller = _tweaksWindowController;
        if (controller != null) {
          await controller.show();
          return;
        }
        final created = await WindowController.create(
          WindowConfiguration(
            arguments: jsonEncode(<String, Object?>{
              'kind': _windowKindTweaks,
              'mainWindowId': _mainWindowId,
            }),
            hiddenAtLaunch: true,
          ),
        );
        _tweaksWindowController = created;
        await created.show();
        return;
      } catch (_) {
        _tweaksWindowController = null;
        // Fallback to in-window dialog if multi-window creation fails.
      }
    }
    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'UI Tweak Lab',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      pageBuilder: (dialogContext, _, __) {
        return _DraggableToolWindow(
          title: 'UI Tweak Lab',
          child: _UiTweaksDialog(
            initial: _uiTweaks,
            onApply: (config) => _setUiTweaks(config),
            onApplyAndReload: (config) async {
              await _setUiTweaks(config);
              _reloadLayoutForTweaks();
            },
            onSaveCurrentAsDefault: (config) async {
              await _saveCurrentUiTweaksAsDefault(config);
            },
            onResetToDefaults: () async {
              await _resetUiTweaks();
              _reloadLayoutForTweaks();
              return _uiTweaks;
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 140),
    );
  }

  void _swapPanels(_PanelType dragged, _PanelType target) {
    if (dragged == target) return;
    final from = _panelOrder.indexOf(dragged);
    final to = _panelOrder.indexOf(target);
    if (from < 0 || to < 0) return;
    setState(() {
      final temp = _panelOrder[from];
      _panelOrder[from] = _panelOrder[to];
      _panelOrder[to] = temp;
    });
    widget.store.updatePanelOrder(_panelOrder.map((p) => p.id).toList());
  }

  void _loadPanelOrderFromStore() {
    final parsed = widget.store.panelOrderIds
        .map(_panelTypeFromId)
        .whereType<_PanelType>()
        .toList(growable: false);
    if (parsed.length != _panelOrder.length) {
      return;
    }
    _panelOrder
      ..clear()
      ..addAll(parsed);
  }

  Widget _buildDraggablePanelSlot({
    required _PanelType type,
    required Widget child,
    bool enableDragDrop = true,
  }) {
    final panelShell = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.transparent, width: 1),
      ),
      child: child,
    );
    if (!enableDragDrop) {
      return panelShell;
    }
    return DragTarget<_PanelType>(
      onWillAcceptWithDetails: (details) => details.data != type,
      onAcceptWithDetails: (details) => _swapPanels(details.data, type),
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: isHighlighted ? 2 : 1,
            ),
          ),
          child: LongPressDraggable<_PanelType>(
            data: type,
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: 280,
                child: Opacity(
                  opacity: 0.92,
                  child: Card(
                    elevation: 10,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.drag_indicator),
                          const SizedBox(width: 8),
                          Text(
                            type == _PanelType.date
                                ? 'Month Header'
                                : type == _PanelType.totals
                                ? 'Totals Panel'
                                : 'Calendar Panel',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.45, child: panelShell),
            child: panelShell,
          ),
        );
      },
    );
  }

  Future<void> _persistUiTweaks() async {
    await _saveUiTweaksToPrefs(_uiTweaks);
  }

  Future<void> _setUiTweaks(UiTweakConfig config) async {
    setState(() {
      _uiTweaks = config;
    });
    await _persistUiTweaks();
  }

  Future<void> _resetUiTweaks() async {
    final defaults = await _loadUiTweaksDefaultFromPrefs();
    await _setUiTweaks(defaults);
  }

  Future<void> _saveCurrentUiTweaksAsDefault(UiTweakConfig config) async {
    await _saveUiTweaksDefaultToPrefs(config);
  }

  void _reloadLayoutForTweaks() {
    setState(() {
      _uiTweaksRevision += 1;
      _monthSummaryCache.clear();
    });
  }

  Future<void> _initMultiWindowBridge() async {
    try {
      final current = await WindowController.fromCurrentEngine();
      _mainWindowId = current.windowId;
      await current.setWindowMethodHandler((call) async {
        if (call.method == 'uiTweaksUpdated') {
          final payload = call.arguments;
          final config = UiTweakConfig.fromJsonString(
            payload is String ? payload : null,
          );
          await _setUiTweaks(config);
          _reloadLayoutForTweaks();
        } else if (call.method == 'uiTweaksDefaultUpdated') {
          // Main window doesn't need an immediate visual update for default
          // baseline changes, but this acknowledges cross-window sync.
        }
        return null;
      });
    } catch (_) {}
  }

  Widget _buildCalendarPanel({
    required BuildContext context,
    required BudgetStore store,
    required DateTime month,
    required UiTweakConfig uiTweaks,
    required bool enableDragDrop,
    required bool enableHoverTooltips,
  }) {
    return _buildDraggablePanelSlot(
      type: _PanelType.calendar,
      enableDragDrop: enableDragDrop,
      child: _CalendarGrid(
        store: store,
        focusedMonth: month,
        uiTweaks: uiTweaks,
        enableHoverTooltips: enableHoverTooltips,
        onOpenDay: (day) => _openDayDialog(context, store, day),
      ),
    );
  }
}

enum _PanelType { date, totals, calendar }

extension on _PanelType {
  String get id {
    switch (this) {
      case _PanelType.date:
        return 'date';
      case _PanelType.totals:
        return 'totals';
      case _PanelType.calendar:
        return 'calendar';
    }
  }
}

_PanelType? _panelTypeFromId(String id) {
  switch (id) {
    case 'date':
      return _PanelType.date;
    case 'totals':
      return _PanelType.totals;
    case 'calendar':
      return _PanelType.calendar;
    default:
      return null;
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.focusedMonth,
    required this.onPrev,
    required this.onNext,
    required this.onMonthSelected,
  });

  final DateTime focusedMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onMonthSelected;

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat.MMMM().format(focusedMonth);
    final yearLabel = focusedMonth.year.toString();
    final now = DateTime.now();
    final isCurrentMonth =
        focusedMonth.year == now.year && focusedMonth.month == now.month;

    return Row(
      children: [
        // Previous button
        IconButton.filledTonal(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
        ),
        const SizedBox(width: 8),

        // Today button (only show if not current month)
        if (!isCurrentMonth)
          TextButton.icon(
            onPressed: () {
              onMonthSelected(DateTime(now.year, now.month, 1));
            },
            icon: const Icon(Icons.today, size: 18),
            label: const Text('Today'),
          ),

        // Month + year controls
        Expanded(
          child: Center(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () async {
                    final selectedMonth = await _showMonthPicker(
                      context,
                      focusedMonth.month,
                    );
                    if (selectedMonth == null) return;
                    onMonthSelected(DateTime(focusedMonth.year, selectedMonth));
                  },
                  child: Text(
                    monthLabel,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final selectedYear = await _showYearPicker(
                      context,
                      focusedMonth.year,
                    );
                    if (selectedYear == null) return;
                    onMonthSelected(DateTime(selectedYear, focusedMonth.month));
                  },
                  child: Text(
                    yearLabel,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Keep layout flexible when Today button is present
        if (!isCurrentMonth) const SizedBox.shrink(),

        const SizedBox(width: 8),
        // Next button
        IconButton.filledTonal(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
        ),
      ],
    );
  }

  Future<int?> _showMonthPicker(BuildContext context, int currentMonth) async {
    final initialIndex = currentMonth.clamp(1, 12) - 1;
    final controller = FixedExtentScrollController(initialItem: initialIndex);
    var selectedMonth = currentMonth.clamp(1, 12);

    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Month'),
        content: SizedBox(
          width: 220,
          height: 220,
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 44,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              selectedMonth = index + 1;
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: 12,
              builder: (context, index) {
                final month = index + 1;
                return Center(
                  child: Text(
                    DateFormat.MMMM().format(DateTime(2000, month)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, selectedMonth),
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Future<int?> _showYearPicker(BuildContext context, int currentYear) async {
    const minYear = 1900;
    const maxYear = 2200;
    final initialIndex = (currentYear.clamp(minYear, maxYear) - minYear)
        .toInt();
    final controller = FixedExtentScrollController(initialItem: initialIndex);
    var selectedYear = currentYear.clamp(minYear, maxYear).toInt();

    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Year'),
        content: SizedBox(
          width: 220,
          height: 220,
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 44,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              selectedYear = minYear + index;
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: maxYear - minYear + 1,
              builder: (context, index) {
                final year = minYear + index;
                return Center(
                  child: Text(
                    '$year',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, selectedYear),
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }
}

class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({
    required this.store,
    required this.uiTweaks,
    required this.monthIncomePennies,
    required this.monthExpensePennies,
    required this.monthBalancePennies,
    required this.runningBalancePennies,
    required this.preferExpandedMetrics,
  });

  final BudgetStore store;
  final UiTweakConfig uiTweaks;
  final int monthIncomePennies;
  final int monthExpensePennies;
  final int monthBalancePennies;
  final int runningBalancePennies;
  final bool preferExpandedMetrics;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // If both balances are hidden, don't show income/expense either
    final showAnyBalance = store.showMonthBalance || store.showRunningBalance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactThreshold = _compactMetricWidthThreshold(
          store.textScaleFactor,
          baseWidth: uiTweaks.compactMetricBaseWidth,
        );
        final iconOnlyMetrics =
            constraints.maxWidth < compactThreshold && !preferExpandedMetrics;
        final metricSpacing = 10.0;
        final availableMetricsWidth = (constraints.maxWidth - 32).clamp(
          0.0,
          double.infinity,
        );
        final minMetricCardWidth =
            (iconOnlyMetrics
                ? uiTweaks.metricCompactMinCardWidth
                : uiTweaks.metricExpandedMinCardWidth) *
            store.textScaleFactor;

        final metricCards = <Widget>[];
        if (showAnyBalance) {
          metricCards.add(
            _MetricCard(
              icon: Icons.arrow_downward,
              iconColor: store.getIncomeColor(isDark),
              label: 'Income',
              value: formatCurrency(store, monthIncomePennies),
              hideTitle: iconOnlyMetrics,
            ),
          );
          metricCards.add(
            _MetricCard(
              icon: Icons.arrow_upward,
              iconColor: store.getExpenseColor(isDark),
              label: 'Expenses',
              value: formatCurrency(store, monthExpensePennies),
              hideTitle: iconOnlyMetrics,
            ),
          );
          if (store.showMonthBalance) {
            metricCards.add(
              _MetricCard(
                icon: Icons.calendar_month,
                iconColor: Theme.of(context).colorScheme.primary,
                label: 'Month Balance',
                value: formatCurrency(store, monthBalancePennies),
                valueColor: monthBalancePennies >= 0
                    ? store.getIncomeColor(isDark)
                    : store.getExpenseColor(isDark),
                hideTitle: iconOnlyMetrics,
              ),
            );
          }
          if (store.showRunningBalance) {
            metricCards.add(
              _MetricCard(
                icon: Icons.account_balance,
                iconColor: Theme.of(context).colorScheme.secondary,
                label: 'Running Balance',
                value: formatCurrency(store, runningBalancePennies),
                valueColor: runningBalancePennies >= 0
                    ? store.getIncomeColor(isDark)
                    : store.getExpenseColor(isDark),
                hideTitle: iconOnlyMetrics,
              ),
            );
          }
          if (store.monthlyBudgetPennies > 0) {
            metricCards.add(
              _MetricCard(
                icon: Icons.savings,
                iconColor: Theme.of(context).colorScheme.tertiary,
                label: 'Budget Remaining',
                value: formatCurrency(
                  store,
                  store.monthlyBudgetPennies - monthExpensePennies,
                ),
                valueColor:
                    (store.monthlyBudgetPennies - monthExpensePennies) >= 0
                    ? store.getIncomeColor(isDark)
                    : store.getExpenseColor(isDark),
                hideTitle: iconOnlyMetrics,
              ),
            );
          }
        }

        final metricColumns = metricCards.isEmpty
            ? 1
            : ((availableMetricsWidth + metricSpacing) ~/
                      (minMetricCardWidth + metricSpacing))
                  .clamp(1, metricCards.length);
        final targetRowWidth = availableMetricsWidth;
        final metricRows = <Widget>[];
        var start = 0;
        while (start < metricCards.length) {
          final remaining = metricCards.length - start;
          final rowCardCount = remaining < metricColumns
              ? remaining
              : metricColumns;
          final rowCardWidth =
              (targetRowWidth - (metricSpacing * (rowCardCount - 1))) /
              rowCardCount;

          final rowChildren = <Widget>[];
          for (var i = 0; i < rowCardCount; i++) {
            if (i > 0) {
              rowChildren.add(SizedBox(width: metricSpacing));
            }
            rowChildren.add(
              SizedBox(width: rowCardWidth, child: metricCards[start + i]),
            );
          }
          metricRows.add(
            Row(mainAxisSize: MainAxisSize.min, children: rowChildren),
          );
          start += rowCardCount;
        }

        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (showAnyBalance)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < metricRows.length; i++) ...[
                          if (i > 0) SizedBox(height: metricSpacing),
                          metricRows[i],
                        ],
                      ],
                    ),
                  ),
                // Show a message if all metrics are hidden
                if (!showAnyBalance)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'All metrics hidden. Enable them in Settings.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).hintColor,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
    this.hideTitle = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;
  final bool hideTitle;

  @override
  Widget build(BuildContext context) {
    final minHeight = hideTitle ? 56.0 : 72.0;
    final horizontalPadding = hideTitle ? 8.0 : 12.0;
    final verticalPadding = hideTitle ? 6.0 : 12.0;

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: hideTitle
          ? Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(icon, size: 18, color: iconColor),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: valueColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: valueColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.store,
    required this.focusedMonth,
    required this.uiTweaks,
    required this.enableHoverTooltips,
    required this.onOpenDay,
  });

  final BudgetStore store;
  final DateTime focusedMonth;
  final UiTweakConfig uiTweaks;
  final bool enableHoverTooltips;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    const spacing = 8.0;
    final textScaler = MediaQuery.textScalerOf(context);
    final uiScale = textScaler.scale(1.0);
    final first = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final firstWeekday = store.getFirstWeekdayOffset(first);
    final daysInMonth = DateTime(
      focusedMonth.year,
      focusedMonth.month + 1,
      0,
    ).day;

    final cellCount = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;
    final rowCount = cellCount ~/ 7;
    final compactDayAmountFormat = NumberFormat.compactCurrency(
      locale: 'en_GB',
      symbol: store.currencySymbol,
      decimalDigits: 0,
    );
    final showHoverRunningBalance =
        enableHoverTooltips && store.showDayRunningBalanceOnHover;
    final hoverRunningBalanceFormat = NumberFormat.currency(
      locale: 'en_GB',
      symbol: store.currencySymbol,
    );
    final hoverRunningBalanceByDayKey = <String, int>{};
    if (showHoverRunningBalance) {
      final monthStart = DateTime(focusedMonth.year, focusedMonth.month, 1);
      final dayBeforeStart = monthStart.subtract(const Duration(days: 1));
      var running = store.runningBalancePennies(dayBeforeStart);
      for (var day = 1; day <= daysInMonth; day++) {
        final key = DateKey.fromDate(
          DateTime(focusedMonth.year, focusedMonth.month, day),
        );
        running += store.dayBalancePennies(key);
        hoverRunningBalanceByDayKey[key] = running;
      }
    }

    final today = DateTime.now();
    final todayKey = DateKey.fromDate(today);
    final isHighContrast = store.highContrastMode;
    final isDark = store.darkMode;
    final magnificationBoost = (uiScale - 1.0).clamp(0.0, 1.5);
    final dayNumberBoxWidthFactor =
        (uiTweaks.dayNumberBoxWidthBase +
                (magnificationBoost * uiTweaks.dayNumberBoxWidthBoost))
            .clamp(0.45, 0.82);
    final dayNumberBoxHeightFactor =
        (uiTweaks.dayNumberBoxHeightBase +
                (magnificationBoost * uiTweaks.dayNumberBoxHeightBoost))
            .clamp(0.32, 0.70);
    final dayNumberBaseFont =
        uiTweaks.dayNumberBaseFont +
        (magnificationBoost * uiTweaks.dayNumberFontBoost);
    final badgeFontScale = 1.0 + (magnificationBoost * uiTweaks.badgeFontBoost);
    final amountFontScale =
        1.0 + (magnificationBoost * uiTweaks.amountFontBoost);

    final incomeBg = isHighContrast
        ? (isDark ? Colors.white : Colors.black)
        : isDark
        ? Color.alphaBlend(
            store.incomeColorDark.withValues(alpha: 0.3),
            Colors.black,
          )
        : Color.alphaBlend(
            store.incomeColorLight.withValues(alpha: 0.3),
            Colors.white,
          );
    final expenseBg = isHighContrast
        ? (isDark ? const Color(0xFFD9D9D9) : const Color(0xFF222222))
        : isDark
        ? Color.alphaBlend(
            store.expenseColorDark.withValues(alpha: 0.3),
            Colors.black,
          )
        : Color.alphaBlend(
            store.expenseColorLight.withValues(alpha: 0.3),
            Colors.white,
          );
    final bothBg = isHighContrast
        ? (isDark ? const Color(0xFFB0B0B0) : const Color(0xFF444444))
        : isDark
        ? Color.alphaBlend(
            store.getBothColor(true).withValues(alpha: 0.32),
            Colors.black,
          )
        : Color.alphaBlend(
            store.getBothColor(false).withValues(alpha: 0.28),
            Colors.white,
          );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultTextStyle(
              style: Theme.of(context).textTheme.labelLarge!,
              child: Row(
                children: store
                    .getDayLabels()
                    .map((day) => Expanded(child: Center(child: Text(day))))
                    .toList(),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth.clamp(
                    0.0,
                    double.infinity,
                  );
                  final maxHeight = constraints.maxHeight.clamp(
                    0.0,
                    double.infinity,
                  );
                  if (maxWidth <= 0 || maxHeight <= 0) {
                    return const SizedBox.shrink();
                  }

                  // Keep a small safety margin to avoid floating-point clipping.
                  final safeWidth = (maxWidth - 0.5).clamp(
                    0.0,
                    double.infinity,
                  );
                  final safeHeight = (maxHeight - 0.5).clamp(
                    0.0,
                    double.infinity,
                  );
                  final widthBasedSize = ((safeWidth - (spacing * 6)) / 7)
                      .clamp(1.0, double.infinity);
                  final heightBasedSize =
                      ((safeHeight - (spacing * (rowCount - 1))) / rowCount)
                          .clamp(1.0, double.infinity);
                  final cellSize = widthBasedSize < heightBasedSize
                      ? widthBasedSize
                      : heightBasedSize;
                  final gridWidth = ((cellSize * 7) + (spacing * 6)).clamp(
                    0.0,
                    safeWidth,
                  );
                  final gridHeight =
                      ((cellSize * rowCount) + (spacing * (rowCount - 1)))
                          .clamp(0.0, safeHeight);

                  return Center(
                    child: SizedBox(
                      width: gridWidth,
                      height: gridHeight,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: 1,
                        ),
                        itemCount: cellCount,
                        itemBuilder: (context, index) {
                          final dayNumber = index - firstWeekday + 1;
                          if (dayNumber < 1 || dayNumber > daysInMonth) {
                            return const SizedBox.shrink();
                          }

                          final day = DateTime(
                            focusedMonth.year,
                            focusedMonth.month,
                            dayNumber,
                          );
                          final dayKey = DateKey.fromDate(day);
                          final hasIncome = store.hasIncome(dayKey);
                          final hasExpense = store.hasExpense(dayKey);
                          final dayBalance = store.dayBalancePennies(dayKey);
                          final entryCount = store.dayEntryCount(dayKey);

                          final bg = hasIncome && hasExpense
                              ? bothBg
                              : hasIncome
                              ? incomeBg
                              : hasExpense
                              ? expenseBg
                              : isHighContrast
                              ? (isDark ? Colors.black : Colors.white)
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest;

                          final isToday = dayKey == todayKey;
                          final showEntryBadge =
                              entryCount > 0 &&
                              cellSize >=
                                  (uiTweaks.showEntryBadgeMinCell * uiScale);
                          final showDayBalance =
                              dayBalance != 0 &&
                              cellSize >=
                                  (uiTweaks.showDayBalanceMinCell * uiScale);
                          Widget cell = InkWell(
                            onTap: () => onOpenDay(day),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(12),
                                border: isToday
                                    ? Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                        width: 2,
                                      )
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  // Day number (centered)
                                  Center(
                                    child: SizedBox(
                                      width: cellSize * dayNumberBoxWidthFactor,
                                      height:
                                          cellSize * dayNumberBoxHeightFactor,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '$dayNumber',
                                          style: TextStyle(
                                            fontSize: dayNumberBaseFont,
                                            fontWeight: isToday
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            fontStyle: isToday
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                            decoration: isToday
                                                ? TextDecoration.underline
                                                : TextDecoration.none,
                                            color: isHighContrast
                                                ? (bg.computeLuminance() > 0.5
                                                      ? Colors.black
                                                      : Colors.white)
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Entry count badge (top-right)
                                  if (showEntryBadge)
                                    Positioned(
                                      top: 3,
                                      right: 3,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isHighContrast
                                              ? (bg.computeLuminance() > 0.5
                                                    ? Colors.black
                                                    : Colors.white)
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          '$entryCount',
                                          style: TextStyle(
                                            fontSize:
                                                (cellSize >= 60
                                                    ? uiTweaks
                                                          .badgeBaseLargeFont
                                                    : uiTweaks
                                                          .badgeBaseSmallFont) *
                                                badgeFontScale,
                                            fontWeight: FontWeight.w600,
                                            color: isHighContrast
                                                ? (bg.computeLuminance() > 0.5
                                                      ? Colors.white
                                                      : Colors.black)
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Net balance (bottom)
                                  if (showDayBalance)
                                    Positioned(
                                      bottom: 2,
                                      left: 0,
                                      right: 0,
                                      child: Text(
                                        compactDayAmountFormat.format(
                                          dayBalance.abs() / 100,
                                        ),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize:
                                              (cellSize >= 65
                                                  ? uiTweaks.amountBaseLargeFont
                                                  : uiTweaks
                                                        .amountBaseSmallFont) *
                                              amountFontScale,
                                          fontWeight: FontWeight.w600,
                                          color: isHighContrast
                                              ? (bg.computeLuminance() > 0.5
                                                    ? Colors.black
                                                    : Colors.white)
                                              : dayBalance > 0
                                              ? store.getIncomeColor(
                                                  store.darkMode,
                                                )
                                              : store.getExpenseColor(
                                                  store.darkMode,
                                                ),
                                        ),
                                      ),
                                    ),
                                  if (isHighContrast)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: bg.computeLuminance() > 0.5
                                                  ? Colors.black
                                                  : Colors.white,
                                              width: isToday ? 3 : 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );

                          if (!showHoverRunningBalance) {
                            return cell;
                          }
                          final runningBalanceForDay =
                              hoverRunningBalanceByDayKey[dayKey] ??
                              store.runningBalancePennies(day);
                          final runningBalanceText = hoverRunningBalanceFormat
                              .format(runningBalanceForDay.abs() / 100);
                          return Tooltip(
                            message: 'Running balance: $runningBalanceText',
                            child: cell,
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayEntriesDialog extends StatelessWidget {
  const _DayEntriesDialog({required this.store, required this.day});

  final BudgetStore store;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final dayKey = DateKey.fromDate(day);
        final incomes = store.incomeForDay(dayKey);
        final expenses = store.expenseForDay(dayKey);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        // Calculate totals
        final totalIncome = incomes.fold<int>(
          0,
          (sum, e) => sum + e.amountPennies,
        );
        final totalExpense = expenses.fold<int>(
          0,
          (sum, e) => sum + e.amountPennies,
        );
        final dayBalance = totalIncome - totalExpense;

        final isMobile = MediaQuery.of(context).size.width < 600;

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Summary card
            _DaySummaryCard(
              store: store,
              totalIncome: totalIncome,
              totalExpense: totalExpense,
              balance: dayBalance,
              entryCount: incomes.length + expenses.length,
            ),
            const SizedBox(height: 20),

            // Entries sections
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSection(
                      context,
                      'Income',
                      incomes,
                      EntryType.income,
                      store.getIncomeColor(isDark),
                      dayKey,
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      'Expenses',
                      expenses,
                      EntryType.expense,
                      store.getExpenseColor(isDark),
                      dayKey,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

        // Use full-screen dialog on mobile
        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(DateFormat.yMd().format(day)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              body: Padding(padding: const EdgeInsets.all(16), child: content),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            final draft = await _showEntryEditor(
                              context,
                              title: 'Add Income',
                              allowRecurrence: true,
                            );
                            if (draft != null) {
                              await store.addEntryWithRecurrence(
                                dayKey,
                                EntryType.income,
                                draft.entry,
                                draft.recurrencePattern,
                                draft.recurrenceOccurrences,
                              );
                            }
                          },
                          icon: const Icon(Icons.arrow_downward),
                          label: const Text('Add Income'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            final draft = await _showEntryEditor(
                              context,
                              title: 'Add Expense',
                              allowRecurrence: true,
                            );
                            if (draft != null) {
                              await store.addEntryWithRecurrence(
                                dayKey,
                                EntryType.expense,
                                draft.entry,
                                draft.recurrencePattern,
                                draft.recurrenceOccurrences,
                              );
                            }
                          },
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text('Add Expense'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // Regular dialog on desktop
        return AlertDialog(
          title: Text('Entries for ${DateFormat.yMd().format(day)}'),
          content: SizedBox(width: 520, child: content),
          actions: [
            TextButton(
              onPressed: () async {
                final draft = await _showEntryEditor(
                  context,
                  title: 'Add Income Entry',
                  allowRecurrence: true,
                );
                if (draft != null) {
                  await store.addEntryWithRecurrence(
                    dayKey,
                    EntryType.income,
                    draft.entry,
                    draft.recurrencePattern,
                    draft.recurrenceOccurrences,
                  );
                }
              },
              child: const Text('Add Income'),
            ),
            TextButton(
              onPressed: () async {
                final draft = await _showEntryEditor(
                  context,
                  title: 'Add Expense Entry',
                  allowRecurrence: true,
                );
                if (draft != null) {
                  await store.addEntryWithRecurrence(
                    dayKey,
                    EntryType.expense,
                    draft.entry,
                    draft.recurrencePattern,
                    draft.recurrenceOccurrences,
                  );
                }
              },
              child: const Text('Add Expense'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<BudgetEntryView> entries,
    EntryType type,
    Color accentColor,
    String dayKey,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              type == EntryType.income
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
              color: accentColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No ${title.toLowerCase()}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).hintColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          )
        else
          ...entries.map(
            (e) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(e.name),
                subtitle: e.note.trim().isEmpty ? null : Text(e.note.trim()),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatCurrency(store, e.amountPennies),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () async {
                        final updated = await _showEntryEditor(
                          context,
                          title:
                              'Edit ${type == EntryType.income ? 'Income' : 'Expense'}',
                          initialName: e.name,
                          initialAmountText: (e.amountPennies / 100)
                              .toStringAsFixed(2),
                          initialNote: e.note,
                          allowRecurrence: false,
                        );
                        if (updated != null) {
                          await store.updateEntry(
                            dayKey,
                            type,
                            e.index,
                            updated.entry,
                          );
                        }
                      },
                      icon: const Icon(Icons.edit, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Entry'),
                            content: Text('Delete "${e.name}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await store.deleteEntry(dayKey, type, e.index);
                        }
                      },
                      icon: const Icon(Icons.delete, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({
    required this.store,
    required this.totalIncome,
    required this.totalExpense,
    required this.balance,
    required this.entryCount,
  });

  final BudgetStore store;
  final int totalIncome;
  final int totalExpense;
  final int balance;
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SummaryItem(
              label: 'Income',
              value: formatCurrency(store, totalIncome),
              color: store.getIncomeColor(isDark),
            ),
            _SummaryItem(
              label: 'Expenses',
              value: formatCurrency(store, totalExpense),
              color: store.getExpenseColor(isDark),
            ),
            _SummaryItem(
              label: 'Balance',
              value: formatCurrency(store, balance),
              color: balance >= 0
                  ? store.getIncomeColor(isDark)
                  : store.getExpenseColor(isDark),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({
    required this.store,
    this.showTweakControls = false,
    this.onOpenUiTweaks,
  });

  final BudgetStore store;
  final bool showTweakControls;
  final VoidCallback? onOpenUiTweaks;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final isMobile = MediaQuery.of(context).size.width < 600;

        final content = SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Budgeting Settings',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Currency Symbol'),
                subtitle: Text(store.currencySymbol),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final value = await _promptText(
                    context,
                    title: 'Currency Symbol',
                    initial: store.currencySymbol,
                    hint: 'e.g. £ or \$',
                  );
                  if (value != null && value.trim().isNotEmpty) {
                    await store.updateBudgetSettings(currency: value.trim());
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Starting Balance'),
                subtitle: Text(
                  formatCurrency(store, store.startingBalancePennies),
                ),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final value = await _promptAmount(
                    context,
                    title: 'Starting Balance',
                    initialPennies: store.startingBalancePennies,
                    symbol: store.currencySymbol,
                  );
                  if (value != null) {
                    await store.updateBudgetSettings(startingBalance: value);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Monthly Budget Target'),
                subtitle: Text(
                  formatCurrency(store, store.monthlyBudgetPennies),
                ),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final value = await _promptAmount(
                    context,
                    title: 'Monthly Budget Target',
                    initialPennies: store.monthlyBudgetPennies,
                    symbol: store.currencySymbol,
                  );
                  if (value != null) {
                    await store.updateBudgetSettings(monthlyBudget: value);
                  }
                },
              ),
              const Divider(height: 32),

              Text(
                'Accessibility',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('High Contrast Mode'),
                subtitle: const Text('Increase contrast for readability.'),
                value: store.highContrastMode,
                onChanged: (v) =>
                    store.updateAccessibilitySettings(highContrast: v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('High Magnification'),
                subtitle: Text(
                  '${(store.textScaleFactor * 100).round()}% text scale',
                ),
              ),
              Slider(
                min: 1.0,
                max: 2.0,
                divisions: 10,
                value: store.textScaleFactor,
                label: '${(store.textScaleFactor * 100).round()}%',
                onChanged: (v) =>
                    store.updateAccessibilitySettings(textScale: v),
              ),
              if (showTweakControls) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: onOpenUiTweaks,
                  icon: const Icon(Icons.tune),
                  label: const Text('Open UI Tweak Lab'),
                ),
              ],
              const Divider(height: 32),

              Text(
                'Color Settings',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _ColorSettingRow(
                label: 'Income (Light Mode)',
                color: store.incomeColorLight,
                onColorSelected: (c) => store.updateColors(incomeLight: c),
              ),
              const SizedBox(height: 8),
              _ColorSettingRow(
                label: 'Income (Dark Mode)',
                color: store.incomeColorDark,
                onColorSelected: (c) => store.updateColors(incomeDark: c),
              ),
              const SizedBox(height: 8),
              _ColorSettingRow(
                label: 'Expense (Light Mode)',
                color: store.expenseColorLight,
                onColorSelected: (c) => store.updateColors(expenseLight: c),
              ),
              const SizedBox(height: 8),
              _ColorSettingRow(
                label: 'Expense (Dark Mode)',
                color: store.expenseColorDark,
                onColorSelected: (c) => store.updateColors(expenseDark: c),
              ),
              const SizedBox(height: 8),
              _ColorSettingRow(
                label: 'Income + Expense (Light Mode)',
                color: store.bothColorLight,
                onColorSelected: (c) => store.updateColors(bothLight: c),
              ),
              const SizedBox(height: 8),
              _ColorSettingRow(
                label: 'Income + Expense (Dark Mode)',
                color: store.bothColorDark,
                onColorSelected: (c) => store.updateColors(bothDark: c),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: store.resetColorsToDefaults,
                icon: const Icon(Icons.restore),
                label: const Text('Reset Colors to Defaults'),
              ),
              const Divider(height: 32),

              Text(
                'Display Settings',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Show Month Balance'),
                subtitle: const Text(
                  'Display balance for current month in totals panel',
                ),
                value: store.showMonthBalance,
                onChanged: (v) => store.updateDisplaySettings(showMonth: v),
              ),
              SwitchListTile(
                title: const Text('Show Running Balance'),
                subtitle: const Text(
                  'Display cumulative balance in totals panel',
                ),
                value: store.showRunningBalance,
                onChanged: (v) => store.updateDisplaySettings(showRunning: v),
              ),
              SwitchListTile(
                title: const Text('Show Day Running Balance On Hover'),
                subtitle: const Text(
                  'Display running balance tooltip when hovering calendar days',
                ),
                value: store.showDayRunningBalanceOnHover,
                onChanged: (v) => store.updateDisplaySettings(
                  showDayRunningBalanceOnHover: v,
                ),
              ),
              SwitchListTile(
                title: const Text('Minimize To System Tray'),
                subtitle: Text(
                  !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
                      ? 'Minimize button hides the app to tray instead of taskbar.'
                      : 'Available on Windows desktop.',
                ),
                value: store.minimizeToTray,
                onChanged:
                    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
                    ? (v) => store.updateDisplaySettings(minimizeToTray: v)
                    : null,
              ),
              const Divider(height: 32),

              Text(
                'Week Start Day',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Sunday')),
                  ButtonSegment(value: 1, label: Text('Monday')),
                  ButtonSegment(value: 6, label: Text('Saturday')),
                ],
                selected: {store.weekStartDay},
                onSelectionChanged: (Set<int> selection) {
                  store.updateWeekStartDay(selection.first);
                },
              ),
              const Divider(height: 32),

              Text(
                'Data Management',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await store.createBackupSnapshot(reason: 'manual');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok ? 'Backup created.' : 'Backup failed.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.backup),
                label: Text('Create Backup Snapshot (${store.backupCount})'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await store.restoreLatestBackup();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Latest backup restored.'
                              : 'No backup to restore.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.history),
                label: const Text('Restore Latest Backup'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final data = store.exportJsonText();
                  await Clipboard.setData(ClipboardData(text: data));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Data exported to clipboard.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.upload_file),
                label: const Text('Export Data (Copy JSON)'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final json = await _promptMultiline(
                    context,
                    title: 'Import JSON Data',
                  );
                  if (json == null || json.trim().isEmpty) return;
                  final ok = await store.importFromJsonText(json);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Import successful.'
                              : 'Import failed. Invalid data.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.download),
                label: const Text('Import Data (Paste JSON)'),
              ),
            ],
          ),
        );

        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Settings'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              body: Padding(padding: const EdgeInsets.all(16), child: content),
            ),
          );
        }

        return AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(width: 560, child: content),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptText(
    BuildContext context, {
    required String title,
    required String initial,
    String? hint,
  }) async {
    final ctrl = TextEditingController(text: initial);
    String? output;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              output = ctrl.text;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return output;
  }

  Future<String?> _promptMultiline(
    BuildContext context, {
    required String title,
  }) async {
    final ctrl = TextEditingController();
    String? output;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: ctrl,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              hintText: '{ ...json... }',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              output = ctrl.text;
              Navigator.pop(context);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
    return output;
  }

  Future<int?> _promptAmount(
    BuildContext context, {
    required String title,
    required int initialPennies,
    required String symbol,
  }) async {
    final ctrl = TextEditingController(
      text: (initialPennies / 100).toStringAsFixed(2),
    );
    int? result;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(prefixText: ' '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = BudgetStore.tryParseAmountToPennies(ctrl.text);
              if (v == null) {
                return;
              }
              result = v;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }
}

class _UiTweaksDialog extends StatefulWidget {
  const _UiTweaksDialog({
    required this.initial,
    required this.onApply,
    required this.onApplyAndReload,
    required this.onSaveCurrentAsDefault,
    required this.onResetToDefaults,
  });

  final UiTweakConfig initial;
  final Future<void> Function(UiTweakConfig config) onApply;
  final Future<void> Function(UiTweakConfig config) onApplyAndReload;
  final Future<void> Function(UiTweakConfig config) onSaveCurrentAsDefault;
  final Future<UiTweakConfig> Function() onResetToDefaults;

  @override
  State<_UiTweaksDialog> createState() => _UiTweaksDialogState();
}

class _DraggableToolWindow extends StatefulWidget {
  const _DraggableToolWindow({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_DraggableToolWindow> createState() => _DraggableToolWindowState();
}

class _DraggableToolWindowState extends State<_DraggableToolWindow> {
  Offset _offset = const Offset(90, 70);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final minMargin = 10.0;
        final toolWidth = (maxW - 20).clamp(520.0, 860.0);
        final toolHeight = (maxH - 20).clamp(420.0, 840.0);
        final clampedX = _offset.dx.clamp(minMargin, maxW - toolWidth - 8);
        final clampedY = _offset.dy.clamp(minMargin, maxH - toolHeight - 8);
        if (clampedX != _offset.dx || clampedY != _offset.dy) {
          _offset = Offset(clampedX, clampedY);
        }

        return Stack(
          children: [
            Positioned(
              left: _offset.dx,
              top: _offset.dy,
              width: toolWidth,
              height: toolHeight,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 14,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _offset += details.delta;
                        });
                      },
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          border: Border(
                            bottom: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.tune, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.title,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UiTweaksDialogState extends State<_UiTweaksDialog> {
  late UiTweakConfig _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  Future<void> _copyValues() async {
    final payload = const JsonEncoder.withIndent('  ').convert(_draft.toMap());
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tweak values copied to clipboard.')),
    );
  }

  Widget _slider({
    required String label,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: description,
                waitDuration: const Duration(milliseconds: 220),
                child: Text('$label: ${value.toStringAsFixed(2)}'),
              ),
            ),
            Tooltip(
              message: description,
              waitDuration: const Duration(milliseconds: 220),
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: value.toStringAsFixed(2),
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Adjust sizing ratios and limits used for day/metric cards. '
                    'Use Apply for live updates or Apply + Reload for a full layout rebuild.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _slider(
                    label: 'Compact Threshold Base Width',
                    description:
                        'Base width used to decide when totals cards switch to compact mode before text-scale is applied.',
                    value: _draft.compactMetricBaseWidth,
                    min: 420,
                    max: 980,
                    divisions: 56,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(compactMetricBaseWidth: v),
                    ),
                  ),
                  _slider(
                    label: 'Metric Compact Min Card Width',
                    description:
                        'Minimum width for totals cards in compact/icon mode.',
                    value: _draft.metricCompactMinCardWidth,
                    min: 100,
                    max: 240,
                    divisions: 28,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(
                        metricCompactMinCardWidth: v,
                      ),
                    ),
                  ),
                  _slider(
                    label: 'Metric Expanded Min Card Width',
                    description:
                        'Minimum width for totals cards in normal mode with labels.',
                    value: _draft.metricExpandedMinCardWidth,
                    min: 120,
                    max: 300,
                    divisions: 36,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(
                        metricExpandedMinCardWidth: v,
                      ),
                    ),
                  ),
                  const Divider(),
                  _slider(
                    label: 'Day Number Box Width Base',
                    description:
                        'Base horizontal fraction of a day tile reserved for the day number.',
                    value: _draft.dayNumberBoxWidthBase,
                    min: 0.45,
                    max: 0.75,
                    divisions: 30,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(dayNumberBoxWidthBase: v),
                    ),
                  ),
                  _slider(
                    label: 'Day Number Box Width Boost',
                    description:
                        'Extra width applied to day-number area as magnification increases.',
                    value: _draft.dayNumberBoxWidthBoost,
                    min: 0.00,
                    max: 0.20,
                    divisions: 40,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(dayNumberBoxWidthBoost: v),
                    ),
                  ),
                  _slider(
                    label: 'Day Number Box Height Base',
                    description:
                        'Base vertical fraction of a day tile reserved for the day number.',
                    value: _draft.dayNumberBoxHeightBase,
                    min: 0.32,
                    max: 0.62,
                    divisions: 30,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(dayNumberBoxHeightBase: v),
                    ),
                  ),
                  _slider(
                    label: 'Day Number Box Height Boost',
                    description:
                        'Extra day-number box height applied under magnification.',
                    value: _draft.dayNumberBoxHeightBoost,
                    min: 0.00,
                    max: 0.20,
                    divisions: 40,
                    onChanged: (v) => setState(
                      () =>
                          _draft = _draft.copyWith(dayNumberBoxHeightBoost: v),
                    ),
                  ),
                  _slider(
                    label: 'Day Number Base Font',
                    description:
                        'Base font size for day numbers before magnification boost.',
                    value: _draft.dayNumberBaseFont,
                    min: 12,
                    max: 30,
                    divisions: 36,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(dayNumberBaseFont: v),
                    ),
                  ),
                  _slider(
                    label: 'Day Number Font Boost',
                    description:
                        'Additional day-number font growth factor with magnification.',
                    value: _draft.dayNumberFontBoost,
                    min: 0,
                    max: 8,
                    divisions: 32,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(dayNumberFontBoost: v),
                    ),
                  ),
                  const Divider(),
                  _slider(
                    label: 'Badge Small Font',
                    description:
                        'Entry-count badge font used when day cells are smaller.',
                    value: _draft.badgeBaseSmallFont,
                    min: 7,
                    max: 14,
                    divisions: 28,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(badgeBaseSmallFont: v),
                    ),
                  ),
                  _slider(
                    label: 'Badge Large Font',
                    description:
                        'Entry-count badge font used when day cells are larger.',
                    value: _draft.badgeBaseLargeFont,
                    min: 8,
                    max: 16,
                    divisions: 32,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(badgeBaseLargeFont: v),
                    ),
                  ),
                  _slider(
                    label: 'Badge Font Boost',
                    description:
                        'Magnification growth multiplier for entry-count badges.',
                    value: _draft.badgeFontBoost,
                    min: 0,
                    max: 1.2,
                    divisions: 48,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(badgeFontBoost: v),
                    ),
                  ),
                  _slider(
                    label: 'Amount Small Font',
                    description: 'Day balance font for smaller day cells.',
                    value: _draft.amountBaseSmallFont,
                    min: 9,
                    max: 18,
                    divisions: 36,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(amountBaseSmallFont: v),
                    ),
                  ),
                  _slider(
                    label: 'Amount Large Font',
                    description: 'Day balance font for larger day cells.',
                    value: _draft.amountBaseLargeFont,
                    min: 10,
                    max: 20,
                    divisions: 40,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(amountBaseLargeFont: v),
                    ),
                  ),
                  _slider(
                    label: 'Amount Font Boost',
                    description:
                        'Magnification growth multiplier for day balance text.',
                    value: _draft.amountFontBoost,
                    min: 0,
                    max: 1.2,
                    divisions: 48,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(amountFontBoost: v),
                    ),
                  ),
                  _slider(
                    label: 'Show Entry Badge Min Cell',
                    description:
                        'Minimum day-cell size required before showing the entry-count badge.',
                    value: _draft.showEntryBadgeMinCell,
                    min: 28,
                    max: 72,
                    divisions: 44,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(showEntryBadgeMinCell: v),
                    ),
                  ),
                  _slider(
                    label: 'Show Day Balance Min Cell',
                    description:
                        'Minimum day-cell size required before showing day balance text.',
                    value: _draft.showDayBalanceMinCell,
                    min: 30,
                    max: 88,
                    divisions: 58,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(showDayBalanceMinCell: v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _copyValues,
                icon: const Icon(Icons.content_copy),
                label: const Text('Copy Values'),
              ),
              TextButton(
                onPressed: () async {
                  await widget.onSaveCurrentAsDefault(_draft);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Current tweak values saved as default.'),
                    ),
                  );
                },
                child: const Text('Save Current as Default'),
              ),
              TextButton(
                onPressed: () async {
                  final resetConfig = await widget.onResetToDefaults();
                  if (!mounted) return;
                  setState(() => _draft = resetConfig);
                },
                child: const Text('Reset to Default'),
              ),
              FilledButton.tonal(
                onPressed: () => widget.onApply(_draft),
                child: const Text('Apply'),
              ),
              FilledButton(
                onPressed: () async {
                  await widget.onApplyAndReload(_draft);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Applied and reloaded.')),
                  );
                },
                child: const Text('Apply + Reload'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorSettingRow extends StatelessWidget {
  const _ColorSettingRow({
    required this.label,
    required this.color,
    required this.onColorSelected,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onColorSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showColorPicker(context),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Color preview circle
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Label
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),

              // Hex value
              Text(
                BudgetStore.colorToHex(color),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showColorPicker(BuildContext context) async {
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(initialColor: color),
    );
    if (selected != null) {
      onColorSelected(selected);
    }
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color selectedColor;

  // Material Design color palette (good defaults for income/expense)
  static final List<Color> palette = [
    // Greens (income)
    const Color(0xFF1B5E20), // Dark green
    const Color(0xFF2E7D32), // Current light income
    const Color(0xFF388E3C),
    const Color(0xFF43A047),
    const Color(0xFF4CAF50),
    const Color(0xFF66BB6A), // Current dark income
    const Color(0xFF81C784),

    // Reds (expense)
    const Color(0xFF8B0000), // Dark red
    const Color(0xFFB71C1C),
    const Color(0xFFC62828), // Current light expense
    const Color(0xFFD32F2F),
    const Color(0xFFE53935),
    const Color(0xFFEF5350), // Current dark expense
    const Color(0xFFF44336),

    // Blues
    const Color(0xFF0D47A1),
    const Color(0xFF1565C0),
    const Color(0xFF1976D2),
    const Color(0xFF1E88E5),
    const Color(0xFF2196F3),
    const Color(0xFF42A5F5),
    const Color(0xFF64B5F6),

    // Oranges/Ambers
    const Color(0xFFE65100),
    const Color(0xFFF57C00),
    const Color(0xFFFB8C00),
    const Color(0xFFFF9800),
    const Color(0xFFFFA726),
    const Color(0xFFFFB74D),

    // Purples
    const Color(0xFF4A148C),
    const Color(0xFF6A1B9A),
    const Color(0xFF7B1FA2),
    const Color(0xFF8E24AA),
    const Color(0xFF9C27B0),
    const Color(0xFFAB47BC),

    // Teals
    const Color(0xFF004D40),
    const Color(0xFF00695C),
    const Color(0xFF00796B),
    const Color(0xFF00897B),
    const Color(0xFF009688),
    const Color(0xFF26A69A),
  ];

  @override
  void initState() {
    super.initState();
    selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Color'),
      content: SizedBox(
        width: 340,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: palette.length,
          itemBuilder: (context, index) {
            final color = palette[index];
            final isSelected = color.toARGB32() == selectedColor.toARGB32();

            return InkWell(
              onTap: () => setState(() => selectedColor = color),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3,
                        )
                      : Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.3),
                          width: 1,
                        ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        color: color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                      )
                    : null,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, selectedColor),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

class _EntryDraft {
  _EntryDraft({
    required this.entry,
    this.recurrencePattern = RecurrencePattern.none,
    this.recurrenceOccurrences = 1,
  });

  final BudgetEntry entry;
  final RecurrencePattern recurrencePattern;
  final int recurrenceOccurrences;
}

Future<_EntryDraft?> _showEntryEditor(
  BuildContext context, {
  required String title,
  String initialName = '',
  String initialAmountText = '',
  String initialNote = '',
  bool allowRecurrence = false,
}) async {
  final nameCtrl = TextEditingController(text: initialName);
  final amountCtrl = TextEditingController(text: initialAmountText);
  final noteCtrl = TextEditingController(text: initialNote);
  final recurrenceCountCtrl = TextEditingController(text: '1');
  final formKey = GlobalKey<FormState>();

  var recurrencePattern = RecurrencePattern.none;
  _EntryDraft? result;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Please enter a name.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: amountCtrl,
                      decoration: const InputDecoration(labelText: 'Amount'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: false,
                      ),
                      validator: (v) {
                        final parsed = BudgetStore.tryParseAmountToPennies(
                          v ?? '',
                        );
                        if (parsed == null) {
                          return 'Please enter a valid amount.';
                        }
                        if (parsed <= 0) {
                          return 'Amount must be greater than 0.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        hintText: 'Add context for this entry',
                      ),
                    ),
                    if (allowRecurrence) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<RecurrencePattern>(
                        initialValue: recurrencePattern,
                        items: RecurrencePattern.values
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) {
                            return;
                          }
                          setState(() => recurrencePattern = v);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Recurring schedule',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: recurrenceCountCtrl,
                        enabled: recurrencePattern != RecurrencePattern.none,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                          signed: false,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Occurrences',
                          helperText: 'How many times to create this entry',
                        ),
                        validator: (v) {
                          if (recurrencePattern == RecurrencePattern.none) {
                            return null;
                          }
                          final count = int.tryParse((v ?? '').trim());
                          if (count == null || count < 1) {
                            return 'Enter a valid occurrence count.';
                          }
                          if (count > 120) {
                            return 'Max 120 occurrences.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) {
                    return;
                  }
                  final pennies = BudgetStore.tryParseAmountToPennies(
                    amountCtrl.text,
                  );
                  if (pennies == null) {
                    return;
                  }

                  final occ =
                      int.tryParse(recurrenceCountCtrl.text.trim()) ?? 1;
                  result = _EntryDraft(
                    entry: BudgetEntry(
                      name: nameCtrl.text.trim(),
                      amountPennies: pennies,
                      note: noteCtrl.text.trim(),
                    ),
                    recurrencePattern: recurrencePattern,
                    recurrenceOccurrences:
                        recurrencePattern == RecurrencePattern.none
                        ? 1
                        : occ.clamp(1, 120),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  return result;
}
