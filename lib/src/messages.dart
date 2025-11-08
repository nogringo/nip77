/// NIP-77 message types for Negentropy protocol
library;

/// Base class for all NIP-77 messages
abstract class Nip77Message {
  /// The subscription ID for this sync session
  final String subscriptionId;

  Nip77Message(this.subscriptionId);

  /// Converts message to JSON array format for Nostr
  List<dynamic> toJson();
}

/// NEG-OPEN: Initiates a Negentropy sync session (Client → Relay)
class NegOpenMessage extends Nip77Message {
  /// Nostr filter criteria (as per NIP-01)
  final Map<String, dynamic> filter;

  /// Hex-encoded initial Negentropy message
  final String initialMessage;

  /// Optional ID size in bytes (default: 32)
  final int? idSize;

  NegOpenMessage({
    required String subscriptionId,
    required this.filter,
    required this.initialMessage,
    this.idSize,
  }) : super(subscriptionId);

  @override
  List<dynamic> toJson() {
    final result = ['NEG-OPEN', subscriptionId, filter, initialMessage];
    if (idSize != null) {
      result.add({'idSize': idSize});
    }
    return result;
  }

  @override
  String toString() =>
      'NEG-OPEN: subscription=$subscriptionId, filter=$filter, msgLen=${initialMessage.length}';
}

/// NEG-MSG: Exchanges Negentropy protocol messages (Bidirectional)
class NegMsgMessage extends Nip77Message {
  /// Hex-encoded Negentropy message
  final String message;

  NegMsgMessage({required String subscriptionId, required this.message})
    : super(subscriptionId);

  /// Creates from JSON array
  factory NegMsgMessage.fromJson(List<dynamic> json) {
    if (json.length < 3 || json[0] != 'NEG-MSG') {
      throw FormatException('Invalid NEG-MSG format');
    }
    return NegMsgMessage(
      subscriptionId: json[1] as String,
      message: json[2] as String,
    );
  }

  @override
  List<dynamic> toJson() => ['NEG-MSG', subscriptionId, message];

  @override
  String toString() =>
      'NEG-MSG: subscription=$subscriptionId, msgLen=${message.length}';
}

/// NEG-ERR: Signals error during sync (Relay → Client)
class NegErrMessage extends Nip77Message {
  /// Error code (e.g., "blocked", "closed")
  final String errorCode;

  /// Optional human-readable error details
  final String? details;

  NegErrMessage({
    required String subscriptionId,
    required this.errorCode,
    this.details,
  }) : super(subscriptionId);

  /// Creates from JSON array
  factory NegErrMessage.fromJson(List<dynamic> json) {
    if (json.length < 3 || json[0] != 'NEG-ERR') {
      throw FormatException('Invalid NEG-ERR format');
    }

    String errorCode = json[2] as String;
    String? details;

    // Parse error code and optional details
    final parts = errorCode.split(':');
    if (parts.length > 1) {
      errorCode = parts[0];
      details = parts.sublist(1).join(':').trim();
    }

    return NegErrMessage(
      subscriptionId: json[1] as String,
      errorCode: errorCode,
      details: details,
    );
  }

  @override
  List<dynamic> toJson() {
    String message = errorCode;
    if (details != null) {
      message = '$errorCode: $details';
    }
    return ['NEG-ERR', subscriptionId, message];
  }

  @override
  String toString() =>
      'NEG-ERR: subscription=$subscriptionId, error=$errorCode'
      '${details != null ? ', details=$details' : ''}';
}

/// NEG-CLOSE: Terminates a sync session (Client → Relay)
class NegCloseMessage extends Nip77Message {
  NegCloseMessage({required String subscriptionId}) : super(subscriptionId);

  @override
  List<dynamic> toJson() => ['NEG-CLOSE', subscriptionId];

  @override
  String toString() => 'NEG-CLOSE: subscription=$subscriptionId';
}

/// Parser for incoming NIP-77 messages
class Nip77MessageParser {
  /// Parses a JSON array into appropriate message type
  static Nip77Message parse(List<dynamic> json) {
    if (json.isEmpty) {
      throw FormatException('Empty message array');
    }

    final messageType = json[0] as String;

    switch (messageType) {
      case 'NEG-MSG':
        return NegMsgMessage.fromJson(json);
      case 'NEG-ERR':
        return NegErrMessage.fromJson(json);
      default:
        throw FormatException('Unknown message type: $messageType');
    }
  }
}
