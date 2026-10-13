// IMEI and serial-number checks (same rules as phone_info.py).

/// True if the digit string passes the Luhn checksum (used by IMEI).
bool luhnIsValid(String number) {
  if (number.isEmpty || !RegExp(r'^\d+$').hasMatch(number)) return false;
  var total = 0;
  final digits = number.split('').reversed.toList();
  for (var i = 0; i < digits.length; i++) {
    var d = int.parse(digits[i]);
    if (i.isOdd) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    total += d;
  }
  return total % 10 == 0;
}

class ImeiInfo {
  ImeiInfo(this.digits)
      : lengthOk = digits.length == 15,
        validChecksum = digits.length == 15 && luhnIsValid(digits);

  factory ImeiInfo.parse(String raw) => ImeiInfo(raw.replaceAll(RegExp(r'\D'), ''));

  final String digits;
  final bool lengthOk;
  final bool validChecksum;

  /// Type Allocation Code: the first 8 digits identify make and model.
  String? get tac => lengthOk ? digits.substring(0, 8) : null;
  String? get serial => lengthOk ? digits.substring(8, 14) : null;
  String? get checkDigit => lengthOk ? digits.substring(14) : null;
}

class SerialInfo {
  SerialInfo(String raw) : normalized = raw.trim().toUpperCase();

  final String normalized;

  /// Apple serials are 10-12 letters/digits.
  bool get plausibleApple =>
      normalized.length >= 10 &&
      normalized.length <= 12 &&
      RegExp(r'^[A-Z0-9]+$').hasMatch(normalized);
}
