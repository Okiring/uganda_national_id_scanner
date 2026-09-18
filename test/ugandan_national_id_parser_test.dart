import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:national_id_scanner/national_id_scanner.dart';

void main() {
  String encoded(String value) => base64.encode(utf8.encode(value));
}
