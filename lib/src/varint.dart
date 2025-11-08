import 'dart:typed_data';

/// Varint encoding/decoding utilities for base-128 variable-length integers
class Varint {
  /// Encodes an unsigned integer into varint format
  /// Uses MSB-first encoding (most significant bit first)
  static Uint8List encode(int value) {
    if (value < 0) {
      throw ArgumentError('Varint can only encode non-negative integers');
    }

    if (value == 0) return Uint8List.fromList([0]);

    final List<int> bytes = [];

    // Extract 7-bit chunks
    while (value != 0) {
      bytes.add(value & 127);
      value = value >>> 7;
    }

    // Reverse to get MSB first
    bytes.reversed.toList();
    final reversed = bytes.reversed.toList();

    // Set continuation bit on all but the last byte
    for (int i = 0; i < reversed.length - 1; i++) {
      reversed[i] |= 128;
    }

    return Uint8List.fromList(reversed);
  }

  /// Decodes a varint from bytes, returns [value, bytesRead]
  /// Uses MSB-first decoding (most significant bit first)
  static VarintDecodeResult decode(Uint8List bytes, [int offset = 0]) {
    int value = 0;
    int bytesRead = 0;

    while (offset + bytesRead < bytes.length) {
      final byte = bytes[offset + bytesRead];
      bytesRead++;

      value = (value << 7) | (byte & 127);

      if ((byte & 128) == 0) {
        return VarintDecodeResult(value, bytesRead);
      }

      if (bytesRead > 10) {
        throw FormatException('Varint too large');
      }
    }

    throw FormatException('Incomplete varint');
  }
}

/// Result of varint decoding operation
class VarintDecodeResult {
  final int value;
  final int bytesRead;

  VarintDecodeResult(this.value, this.bytesRead);
}
