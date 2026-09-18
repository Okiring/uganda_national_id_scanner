import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:national_id_scanner_example/main.dart';

void main() {
  testWidgets('loads scanner demo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScannerDemoPage()));
    expect(find.text('Scan National ID'), findsOneWidget);
  });
}
