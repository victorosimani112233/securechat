import 'dart:convert';

import 'package:cryptography/cryptography.dart';

String normalizePhoneDigits(String input) {
  final digits = input.replaceAll(RegExp('[^0-9]'), '');
  if (digits.startsWith('05') && digits.length == 11) {
    return '90${digits.substring(1)}';
  }
  if (digits.startsWith('5') && digits.length == 10) return '90$digits';
  return digits;
}

Future<String> hashPhoneNumber(String input) async {
  final hash = await Sha256().hash(utf8.encode(normalizePhoneDigits(input)));
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
