/// Result of a successful Ugandan National ID barcode scan.
class NationalIdScanResult {
  const NationalIdScanResult({
    required this.rawValue,
    required this.surname,
    required this.givenName,
    required this.dateOfBirth,
    required this.expires,
    required this.nin,
    required this.cardNumber,
  });

  /// Raw PDF417 barcode text returned by the native scanner.
  final String rawValue;

  final String surname;
  final String givenName;
  final String dateOfBirth;
  final String expires;
  final String nin;
  final String cardNumber;

  Map<String, String> toMap() => {
        'surname': surname,
        'givenName': givenName,
        'dateOfBirth': dateOfBirth,
        'expires': expires,
        'nin': nin,
        'cardNumber': cardNumber,
      };

  @override
  String toString() =>
      'NationalIdScanResult(surname: $surname, givenName: $givenName, '
      'nin: $nin, cardNumber: $cardNumber, dateOfBirth: $dateOfBirth, '
      'expires: $expires)';
}
