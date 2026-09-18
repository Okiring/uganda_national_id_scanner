import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:national_id_scanner/src/national_id_scan_result.dart';
import 'package:national_id_scanner/src/ugandan_national_id_parser.dart';

/// Opens the native National ID scanner and returns a parsed result.
///
/// Returns `null` when the user cancels. Throws [NationalIdScanException] when
/// a barcode is read but is not a valid Ugandan National ID payload.
class NationalIdScanner {
  const NationalIdScanner._();

  static const MethodChannel _channel =
      MethodChannel('com.uganda.scanner/national_id_scanner');

  /// Launches the native camera scanner UI.
  static Future<NationalIdScanResult?> scan() async {
    final rawValue = await _channel.invokeMethod<String>('scan');

    if (rawValue == null) return null;

    if (kDebugMode) {
      debugPrint('National ID barcode received text: $rawValue');
    }

    final parsed = UgandanNationalIdParser.tryParse(rawValue);
    if (parsed == null) {
      throw const NationalIdScanException(
        'A PDF417 barcode was read, but it did not contain valid National ID data.',
      );
    }

    if (kDebugMode) {
      debugPrint('National ID barcode parsed data: $parsed');
    }

    return parsed;
  }
}

/// Thrown when native scanning succeeds but Flutter-side parsing fails.
class NationalIdScanException implements Exception {
  const NationalIdScanException(this.message);

  final String message;

  @override
  String toString() => 'NationalIdScanException: $message';
}
