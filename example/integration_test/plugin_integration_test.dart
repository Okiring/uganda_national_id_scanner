import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:national_id_scanner/national_id_scanner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('parser is available from the package API', (tester) async {
    expect(UgandanNationalIdParser.tryParse('one;two'), isNull);
  });
}
