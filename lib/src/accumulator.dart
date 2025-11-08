import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'varint.dart';

/// Accumulator for computing fingerprints in the Negentropy protocol
/// This is a 256-bit integer that supports addition with carry
class Accumulator {
  Uint8List buf = Uint8List(32); // 256 bits

  /// Set the accumulator to zero
  void setToZero() {
    buf = Uint8List(32);
  }

  /// Add another 256-bit buffer to this accumulator with carry
  void add(Uint8List otherBuf) {
    int carry = 0;

    // Add byte by byte from right to left (little-endian)
    for (int i = 0; i < 32; i++) {
      final sum = buf[i] + otherBuf[i] + carry;
      buf[i] = sum & 0xFF;
      carry = sum >> 8;
    }
  }

  /// Get the fingerprint from this accumulator
  /// Fingerprint = SHA256(accumulator || varint(n))[0..16]
  Uint8List getFingerprint(int n) {
    final countVarint = Varint.encode(n);
    final input = Uint8List(32 + countVarint.length);
    input.setRange(0, 32, buf);
    input.setRange(32, input.length, countVarint);

    final hash = sha256.convert(input).bytes;
    return Uint8List.fromList(hash.sublist(0, 16));
  }
}
