import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:national_id_scanner/src/national_id_scan_result.dart';

/// Parses semicolon-delimited Ugandan National ID PDF417 payloads.
///
/// Supports two layouts:
///
/// **Three-name / middle-name slot** (8+ fields):
/// 0 surname, 1 givenName, 2 middleName (optional/blank), 3 DOB,
/// 4 issued, 5 expires, 6 nin, 7 cardNumber
///
/// **Two-name** (middle-name field omitted, 7+ fields):
/// 0 surname, 1 givenName, 2 DOB, 3 issued, 4 expires, 5 nin, 6 cardNumber
///
/// Detection: if field 2 looks like `ddMMyyyy`, the two-name layout is used.
class UgandanNationalIdParser {
  const UgandanNationalIdParser._();

  /// Returns a [NationalIdScanResult] when [rawValue] is a valid Uganda NID
  /// barcode payload; otherwise returns `null`.
  static NationalIdScanResult? tryParse(String rawValue) {
    // Keep empty segments so a blank middle-name slot does not shift fields.
    final items = rawValue.split(';');
    if (items.length < 7) return null;

    try {
      final surname = _requireName(items[0]);
      final firstGivenName = _requireName(items[1]);
      if (surname == null || firstGivenName == null) return null;

      final hasMiddleNameSlot = !_looksLikeDate(items[2]);
      if (hasMiddleNameSlot && items.length < 8) return null;

      final otherGivenName =
          hasMiddleNameSlot ? _optionalName(items[2]) : null;
      final givenName = [
        firstGivenName,
        if (otherGivenName != null) otherGivenName,
      ].join(' ');

      final dateOfBirthIndex = hasMiddleNameSlot ? 3 : 2;
      final expiresIndex = hasMiddleNameSlot ? 5 : 4;
      final ninIndex = hasMiddleNameSlot ? 6 : 5;
      final cardNumberIndex = hasMiddleNameSlot ? 7 : 6;

      final nin = items[ninIndex].trim();
      final cardNumber = items[cardNumberIndex].trim();
      if (nin.isEmpty || cardNumber.isEmpty) return null;

      return NationalIdScanResult(
        rawValue: rawValue,
        surname: surname,
        givenName: givenName,
        dateOfBirth: _formatDate(items[dateOfBirthIndex]),
        expires: _formatDate(items[expiresIndex]),
        nin: nin,
        cardNumber: cardNumber,
      );
    } catch (_) {
      return null;
    }
  }

  /// Decodes a required base64 name field. Returns `null` when missing/invalid.
  static String? _requireName(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final decoded = String.fromCharCodes(base64.decode(value)).trim();
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return null;
    }
  }

  /// Decodes an optional base64 name field. Invalid or blank values are ignored.
  static String? _optionalName(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final decoded = String.fromCharCodes(base64.decode(value)).trim();
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeDate(String value) {
    final trimmed = value.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(trimmed)) return false;

    try {
      final day = int.parse(trimmed.substring(0, 2));
      final month = int.parse(trimmed.substring(2, 4));
      final year = int.parse(trimmed.substring(4, 8));
      return day >= 1 &&
          day <= 31 &&
          month >= 1 &&
          month <= 12 &&
          year >= 1900 &&
          year <= 2100;
    } catch (_) {
      return false;
    }
  }

  static String _formatDate(String value) {
    if (value.length != 8) return value;

    try {
      final day = value.substring(0, 2);
      final month = value.substring(2, 4);
      final year = value.substring(4, 8);
      final date = DateTime.parse('$year-$month-$day');
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      return value;
    }
  }
}
