import 'package:flutter/material.dart';
import 'package:national_id_scanner/national_id_scanner.dart';

void main() {
  runApp(const MaterialApp(home: ScannerDemoPage()));
}

class ScannerDemoPage extends StatefulWidget {
  const ScannerDemoPage({super.key});

  @override
  State<ScannerDemoPage> createState() => _ScannerDemoPageState();
}

class _ScannerDemoPageState extends State<ScannerDemoPage> {
  String _status = 'Tap scan to open the National ID scanner.';
  NationalIdScanResult? _result;

  Future<void> _scan() async {
    setState(() {
      _status = 'Scanning...';
      _result = null;
    });

    try {
      final result = await NationalIdScanner.scan();
      if (!mounted) return;

      if (result == null) {
        setState(() => _status = 'Scan cancelled.');
        return;
      }

      setState(() {
        _result = result;
        _status = 'Scan successful.';
      });
    } on NationalIdScanException catch (error) {
      if (!mounted) return;
      setState(() => _status = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('National ID Scanner')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 16),
            FilledButton(onPressed: _scan, child: const Text('Scan National ID')),
            if (result != null) ...[
              const SizedBox(height: 24),
              Text('Surname: ${result.surname}'),
              Text('Given name: ${result.givenName}'),
              Text('NIN: ${result.nin}'),
              Text('Card: ${result.cardNumber}'),
              Text('DOB: ${result.dateOfBirth}'),
              Text('Expires: ${result.expires}'),
              const SizedBox(height: 12),
              Text('Raw:\n${result.rawValue}'),
            ],
          ],
        ),
      ),
    );
  }
}
