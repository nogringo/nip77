import 'dart:typed_data';

/// Represents a Negentropy record with timestamp and event ID
class NegentropyRecord implements Comparable<NegentropyRecord> {
  final int timestamp; // 64-bit timestamp (seconds)
  final Uint8List id; // 256-bit event ID

  NegentropyRecord(this.timestamp, this.id) {
    if (id.length != 32) {
      throw ArgumentError('Event ID must be exactly 32 bytes (256 bits)');
    }
  }

  /// Creates a record from hex-encoded ID
  factory NegentropyRecord.fromHex(int timestamp, String hexId) {
    if (hexId.length != 64) {
      throw ArgumentError('Hex ID must be 64 characters (32 bytes)');
    }

    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = int.parse(hexId.substring(i * 2, i * 2 + 2), radix: 16);
    }

    return NegentropyRecord(timestamp, bytes);
  }

  /// Converts ID to hex string
  String get idHex {
    return id.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  @override
  int compareTo(NegentropyRecord other) {
    // First compare by timestamp
    if (timestamp != other.timestamp) {
      return timestamp.compareTo(other.timestamp);
    }

    // Then compare by ID (lexicographic)
    for (int i = 0; i < 32; i++) {
      if (id[i] != other.id[i]) {
        return id[i].compareTo(other.id[i]);
      }
    }

    return 0;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NegentropyRecord) return false;
    return timestamp == other.timestamp && _bytesEqual(id, other.id);
  }

  @override
  int get hashCode => timestamp.hashCode ^ id.fold(0, (a, b) => a ^ b);

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'NegentropyRecord(timestamp: $timestamp, id: $idHex)';
}
