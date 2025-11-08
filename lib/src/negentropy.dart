import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'negentropy_record.dart';
import 'accumulator.dart';
import 'varint.dart';

/// Negentropy protocol version
const int protocolVersion = 0x61; // v1

/// Protocol modes
enum NegentropyMode {
  skip(0),
  fingerprint(1),
  idList(2);

  final int value;
  const NegentropyMode(this.value);
}

/// Result of a reconciliation operation
class ReconciliationResult {
  /// IDs we have that the other side doesn't
  final List<String> haveIds;

  /// IDs the other side has that we don't
  final List<String> needIds;

  ReconciliationResult({required this.haveIds, required this.needIds});

  @override
  String toString() =>
      'ReconciliationResult(have: ${haveIds.length}, need: ${needIds.length})';
}

/// Simple client-only Negentropy protocol implementation
class Negentropy {
  final List<NegentropyRecord> _records;
  final int frameSizeLimit;

  bool _isInitialized = false;
  int _lastTimestampOut = 0;
  int _lastTimestampIn = 0;

  final Set<String> _haveIds = {};
  final Set<String> _needIds = {};

  Negentropy({
    required List<NegentropyRecord> records,
    this.frameSizeLimit = 60000,
  }) : _records = List.from(records) {
    // Sort records by timestamp, then by ID
    _records.sort();
  }

  /// Initializes and returns the initial message for the client
  Uint8List initiate() {
    if (_isInitialized) {
      throw StateError('Already initialized');
    }
    _isInitialized = true;

    final output = BytesBuilder();

    // Protocol version
    output.addByte(protocolVersion);

    // Split range and add to output (use max bound for full range)
    _splitRange(0, _records.length, 0x7FFFFFFFFFFFFFFF, Uint8List(0), output);

    return output.toBytes();
  }

  /// Process a message from the server and return the next message (or null if done)
  Uint8List? reconcile(Uint8List query) {
    if (!_isInitialized) {
      throw StateError('Not initialized. Call initiate() first.');
    }

    _lastTimestampIn = 0;
    _lastTimestampOut = 0;

    int offset = 0;

    // Validate protocol version
    if (query[offset] != protocolVersion) {
      throw FormatException('Unsupported protocol version: ${query[offset]}');
    }
    offset++;

    final fullOutput = BytesBuilder();
    fullOutput.addByte(protocolVersion);

    int prevIndex = 0;
    int prevBoundTimestamp = 0;
    Uint8List prevBoundId = Uint8List(0);
    bool skip = false;

    // Process ranges from server
    while (offset < query.length) {
      final o = BytesBuilder(); // Separate output buffer for this range

      // Decode bound
      final boundResult = _decodeBound(query, offset);
      offset = boundResult.offset;
      final currBoundTimestamp = boundResult.timestamp;
      final currBoundId = boundResult.id;
      final currBoundIdLen = boundResult.idLen;

      // Decode mode (if more data available)
      if (offset >= query.length) {
        break; // No mode, end of message
      }

      final modeResult = Varint.decode(query, offset);
      offset += modeResult.bytesRead;
      final mode = modeResult.value;

      // Find upper bound in our records
      final lower = prevIndex;
      final upper = _findUpperBound(prevIndex, currBoundTimestamp, currBoundId);

      // Helper to prepend SKIP if needed
      void doSkip() {
        if (skip) {
          skip = false;
          // Encode previous bound + SKIP mode
          _encodeTimestamp(prevBoundTimestamp, o);
          o.add(
            Varint.encode(prevBoundId.length > 32 ? 0 : prevBoundId.length),
          );
          if (prevBoundId.isNotEmpty && prevBoundId.length <= 32) {
            o.add(prevBoundId);
          }
          o.add(Varint.encode(NegentropyMode.skip.value));
        }
      }

      bool shouldSkip = false;

      if (mode == NegentropyMode.skip.value) {
        shouldSkip = true;
      } else if (mode == NegentropyMode.fingerprint.value) {
        // Decode their fingerprint
        final theirFingerprint = Uint8List.fromList(
          query.sublist(offset, offset + 16),
        );
        offset += 16;

        // Calculate our fingerprint for this range
        final ourFingerprint = _calculateFingerprint(lower, upper);

        // Compare fingerprints
        if (!_fingerprintsMatch(theirFingerprint, ourFingerprint)) {
          // Fingerprints don't match - split our range
          doSkip();
          final actualIdPrefix = currBoundIdLen > 0
              ? currBoundId.sublist(0, currBoundIdLen)
              : Uint8List(0);
          _splitRange(lower, upper, currBoundTimestamp, actualIdPrefix, o);
          shouldSkip = false;
        } else {
          shouldSkip = true;
        }
      } else if (mode == NegentropyMode.idList.value) {
        // Decode number of IDs
        final numIdsResult = Varint.decode(query, offset);
        offset += numIdsResult.bytesRead;
        final numIds = numIdsResult.value;

        // Decode IDs from server
        final theirIds = <String>{};
        for (int i = 0; i < numIds; i++) {
          final id = query.sublist(offset, offset + 32);
          offset += 32;
          theirIds.add(hex.encode(id));
        }

        // Compare with our IDs in this range
        for (int i = lower; i < upper; i++) {
          final ourId = _records[i].idHex;
          if (!theirIds.contains(ourId)) {
            _haveIds.add(ourId);
          } else {
            theirIds.remove(ourId);
          }
        }

        // Remaining IDs in theirIds are ones we need
        _needIds.addAll(theirIds);

        // As client, we don't respond to IdList - just accept the IDs
        shouldSkip = true;
      }

      if (shouldSkip) {
        skip = true;
      }

      // Append this range's output to full output
      final rangeOutput = o.toBytes();
      if (rangeOutput.isNotEmpty) {
        fullOutput.add(rangeOutput);
      }

      prevIndex = upper;
      prevBoundTimestamp = currBoundTimestamp;
      prevBoundId = currBoundIdLen > 0
          ? currBoundId.sublist(0, currBoundIdLen)
          : Uint8List(0);
    }

    // If output only has version byte (1 byte), we're done
    final bytes = fullOutput.toBytes();
    return bytes.length == 1 ? null : bytes;
  }

  /// Get the reconciliation result
  ReconciliationResult? getResult() {
    return ReconciliationResult(
      haveIds: _haveIds.toList(),
      needIds: _needIds.toList(),
    );
  }

  /// Split a range into buckets or send as ID list
  /// upperBoundTimestamp and upperBoundId define the upper bound of this range
  void _splitRange(
    int lower,
    int upper,
    int upperBoundTimestamp,
    Uint8List upperBoundId,
    BytesBuilder output,
  ) {
    final numElems = upper - lower;

    if (numElems < 32) {
      // Small range: send as ID list
      // Use the provided upper bound (NOT calculated from records)
      _encodeTimestamp(upperBoundTimestamp, output);
      output.add(Varint.encode(upperBoundId.length));
      if (upperBoundId.isNotEmpty) {
        output.add(upperBoundId);
      }

      output.add(Varint.encode(NegentropyMode.idList.value));
      output.add(Varint.encode(numElems));

      for (int i = lower; i < upper; i++) {
        output.add(_records[i].id);
      }
    } else {
      // Large range: split into 16 buckets with fingerprints
      final buckets = 16;
      final itemsPerBucket = numElems ~/ buckets;
      final bucketsWithExtra = numElems % buckets;
      int curr = lower;

      for (int i = 0; i < buckets; i++) {
        final bucketSize = itemsPerBucket + (i < bucketsWithExtra ? 1 : 0);

        // Calculate fingerprint for this bucket [curr, curr+bucketSize)
        final fingerprint = _calculateFingerprint(curr, curr + bucketSize);

        curr += bucketSize;

        // Encode bound (points to start of NEXT range)
        if (curr == upper) {
          // Last bucket - use the provided upper bound parameter
          _encodeTimestamp(upperBoundTimestamp, output);
          output.add(Varint.encode(upperBoundId.length));
          if (upperBoundId.isNotEmpty) {
            output.add(upperBoundId);
          }
        } else {
          // Bound is at position curr (start of next bucket)
          // Calculate minimal bound between curr-1 and curr
          final prevRecord = _records[curr - 1];
          final currRecord = _records[curr];

          if (currRecord.timestamp != prevRecord.timestamp) {
            // Different timestamps - just use timestamp, no ID prefix needed
            _encodeTimestamp(currRecord.timestamp, output);
            output.add(Varint.encode(0));
          } else {
            // Same timestamp - need ID prefix to distinguish
            int prefixLen = 0;
            for (int j = 0; j < 32; j++) {
              prefixLen++;
              if (prevRecord.id[j] != currRecord.id[j]) break;
            }

            _encodeTimestamp(currRecord.timestamp, output);
            output.add(Varint.encode(prefixLen));
            output.add(currRecord.id.sublist(0, prefixLen));
          }
        }

        // Encode mode and fingerprint
        output.add(Varint.encode(NegentropyMode.fingerprint.value));
        output.add(fingerprint);
      }
    }
  }

  /// Calculate fingerprint for a range of records
  Uint8List _calculateFingerprint(int lower, int upper) {
    final accumulator = Accumulator();
    accumulator.setToZero();

    for (int i = lower; i < upper; i++) {
      accumulator.add(_records[i].id);
    }

    return accumulator.getFingerprint(upper - lower);
  }

  /// Encode timestamp with delta encoding
  void _encodeTimestamp(int timestamp, BytesBuilder output) {
    if (timestamp == 0x7FFFFFFFFFFFFFFF) {
      output.add(Varint.encode(0));
      _lastTimestampOut = 0x7FFFFFFFFFFFFFFF;
    } else {
      final delta = timestamp - _lastTimestampOut;
      output.add(Varint.encode(delta + 1));
      _lastTimestampOut = timestamp;
    }
  }

  /// Decode bound from message
  ({int timestamp, Uint8List id, int idLen, int offset}) _decodeBound(
    Uint8List data,
    int offset,
  ) {
    // Decode timestamp
    final tsResult = Varint.decode(data, offset);
    offset += tsResult.bytesRead;

    int timestamp;
    if (tsResult.value == 0) {
      timestamp = 0x7FFFFFFFFFFFFFFF;
      _lastTimestampIn = 0x7FFFFFFFFFFFFFFF;
    } else {
      timestamp = tsResult.value - 1 + _lastTimestampIn;
      _lastTimestampIn = timestamp;
    }

    // Decode ID prefix length
    final idLenResult = Varint.decode(data, offset);
    offset += idLenResult.bytesRead;
    final idLen = idLenResult.value;

    // Decode ID prefix
    final id = Uint8List(32);
    if (idLen > 0 && offset + idLen <= data.length) {
      id.setRange(0, idLen, data.sublist(offset, offset + idLen));
      offset += idLen;
    }

    return (timestamp: timestamp, id: id, idLen: idLen, offset: offset);
  }

  /// Find upper bound in records for given timestamp and ID prefix
  int _findUpperBound(int start, int timestamp, Uint8List idPrefix) {
    if (timestamp == 0x7FFFFFFFFFFFFFFF) {
      return _records.length;
    }

    // Binary search for timestamp
    int left = start;
    int right = _records.length;

    while (left < right) {
      final mid = (left + right) ~/ 2;
      if (_records[mid].timestamp < timestamp) {
        left = mid + 1;
      } else if (_records[mid].timestamp > timestamp) {
        right = mid;
      } else {
        // Same timestamp, check ID prefix
        if (_compareIdPrefix(_records[mid].id, idPrefix) < 0) {
          left = mid + 1;
        } else {
          right = mid;
        }
      }
    }

    return left;
  }

  /// Compare ID with prefix
  int _compareIdPrefix(Uint8List id, Uint8List prefix) {
    for (int i = 0; i < prefix.length && i < id.length; i++) {
      if (id[i] < prefix[i]) return -1;
      if (id[i] > prefix[i]) return 1;
    }
    return 0;
  }

  /// Check if fingerprints match
  bool _fingerprintsMatch(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Extension to convert bytes to hex
extension Nip77Hex on Uint8List {
  String toHex() => hex.encode(this);
}

extension HexToBytes on String {
  Uint8List fromHex() => Uint8List.fromList(hex.decode(this));
}
