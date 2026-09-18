# National ID Scanner

Native PDF417 barcode scanner for **Ugandan National IDs**, for Android and iOS.

- **Android:** CameraX + ZXing-C++ (Java), minSdk **21**
- **iOS:** AVFoundation + ZXing-C++ (Swift), iOS **15.0+**
- **Flutter:** Parses the raw barcode into a typed result

## Install

```yaml
dependencies:
  national_id_scanner:
    git: <path-to-version>
```

### iOS

Host apps must target **iOS 15.0+**. Add a camera usage description to your host app `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to scan your National ID barcode.</string>
```

### Android

Camera permission is declared by the plugin. Ensure your host app requests/runtime-grants camera access as needed (the scanner activity also requests it).

## Usage

```dart
import 'package:national_id_scanner/national_id_scanner.dart';

try {
  final result = await NationalIdScanner.scan();
  if (result == null) {
    // User cancelled
    return;
  }

  print(result.rawValue);
  print(result.surname);
  print(result.givenName);
  print(result.nin);
  print(result.cardNumber);
  print(result.dateOfBirth);
  print(result.expires);
} on NationalIdScanException catch (error) {
  // Barcode read, but not a valid Ugandan National ID payload
  print(error.message);
}
```
