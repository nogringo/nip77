import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'varint.dart';
import 'negentropy_record.dart';

/// Calculates fingerprints for Negentropy ranges
class Fingerprint {
  /// Calculates fingerprint for a list of records
  ///
  /// Algorithm:
  /// 1. Sum all IDs mod 2^256
  /// 2. Concatenate element count as varint
  /// 3. SHA-256 hash
  /// 4. Extract first 16 bytes
  static Uint8List calculate(List<NegentropyRecord> records) {
    // Sum IDs mod 2^256
    final sum = Uint8List(32); // 256 bits

    for (final record in records) {
      _addMod256(sum, record.id);
    }

    // Concatenate count as varint
    final countVarint = Varint.encode(records.length);
    final combined = Uint8List(32 + countVarint.length);
    combined.setRange(0, 32, sum);
    combined.setRange(32, combined.length, countVarint);

    // SHA-256 hash and take first 16 bytes
    final hash = sha256.convert(combined).bytes;
    return Uint8List.fromList(hash.sublist(0, 16));
  }

  /// Adds two 256-bit numbers mod 2^256 (in-place)
  static void _addMod256(Uint8List a, Uint8List b) {
    int carry = 0;
    for (int i = 0; i < 32; i++) {
      final sum = a[i] + b[i] + carry;
      a[i] = sum & 0xFF;
      carry = sum >> 8;
    }
  }

  /// Converts fingerprint to hex string
  static String toHex(Uint8List fingerprint) {
    return fingerprint.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Converts hex string to fingerprint
  static Uint8List fromHex(String hex) {
    if (hex.length != 32) {
      throw ArgumentError('Fingerprint hex must be 32 characters (16 bytes)');
    }

    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
