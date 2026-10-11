import 'package:intl/intl.dart';

/// Centralized Date and Time formatting utility for Fresh Cane.
/// Ensures that all UTC timestamps stored in Supabase are accurately
/// converted to local Indian Standard Time (IST / Asia/Kolkata) across
/// Server, Cashier, and Admin interfaces.
class AppDateTime {
  AppDateTime._();

  static final DateFormat _timeFormat = DateFormat('hh:mm a');
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _shortDateFormat = DateFormat('dd MMM');

  /// Safely parse any dynamic date input (String, DateTime, or null)
  /// and convert to local system time (IST).
  static DateTime? parseToLocal(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) {
      return value.isUtc ? value.toLocal() : value;
    }
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    try {
      final parsed = DateTime.parse(str);
      return parsed.isUtc ? parsed.toLocal() : parsed;
    } catch (_) {
      try {
        final parsed = DateTime.tryParse(str);
        return parsed != null ? (parsed.isUtc ? parsed.toLocal() : parsed) : null;
      } catch (_) {
        return null;
      }
    }
  }

  /// Format time as `hh:mm a` (e.g., "11:45 PM").
  static String formatTime(dynamic value, {String fallback = '-'}) {
    final dt = parseToLocal(value);
    if (dt == null) return fallback;
    return _timeFormat.format(dt);
  }

  /// Format date as `dd MMM yyyy` (e.g., "08 Oct 2026").
  static String formatDate(dynamic value, {String fallback = '-'}) {
    final dt = parseToLocal(value);
    if (dt == null) return fallback;
    return _dateFormat.format(dt);
  }

  /// Format short date as `dd MMM` (e.g., "08 Oct").
  static String formatShortDate(dynamic value, {String fallback = '-'}) {
    final dt = parseToLocal(value);
    if (dt == null) return fallback;
    return _shortDateFormat.format(dt);
  }

  /// Format combined date and time as `dd MMM yyyy, hh:mm a` (e.g., "08 Oct 2026, 11:45 PM").
  static String formatDateTime(dynamic value, {String fallback = '-'}) {
    final dt = parseToLocal(value);
    if (dt == null) return fallback;
    return _dateTimeFormat.format(dt);
  }
}
