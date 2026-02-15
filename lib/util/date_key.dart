import 'package:intl/intl.dart';

/// Stable `YYYY-MM-DD` key used by the legacy Python app.
class DateKey {
  static final DateFormat _fmt = DateFormat('yyyy-MM-dd');

  static String fromDate(DateTime dt) {
    final d = DateTime(dt.year, dt.month, dt.day);
    return _fmt.format(d);
  }

  static DateTime? tryParse(String key) {
    try {
      final dt = DateTime.parse(key);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {
      return null;
    }
  }
}

