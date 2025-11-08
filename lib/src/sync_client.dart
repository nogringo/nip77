import 'dart:async';
import 'dart:convert';
import 'negentropy.dart';
import 'negentropy_record.dart';
import 'messages.dart';

/// Callback type for sending messages to the relay
typedef MessageSender = void Function(List<dynamic> message);

/// Callback type for receiving sync results
typedef SyncResultCallback = void Function(ReconciliationResult result);

/// Callback type for error handling
typedef ErrorCallback = void Function(String error);

/// High-level client API for NIP-77 Negentropy syncing
class Nip77SyncClient {
  final MessageSender _sendMessage;
  final Map<String, _SyncSession> _sessions = {};

  Nip77SyncClient({required MessageSender sendMessage})
      : _sendMessage = sendMessage;

  /// Starts a new sync session with the given records and filter
  ///
  /// Returns the subscription ID for this session
  String startSync({
    required List<NegentropyRecord> records,
    required Map<String, dynamic> filter,
    SyncResultCallback? onResult,
    ErrorCallback? onError,
  }) {
    // Generate unique subscription ID
    final subscriptionId =
        'neg_${DateTime.now().millisecondsSinceEpoch}_${_sessions.length}';

    // Create Negentropy instance
    final negentropy = Negentropy(
      records: records,
    );

    // Initialize and get first message
    final initialMessage = negentropy.initiate();

    // Create session
    final session = _SyncSession(
      subscriptionId: subscriptionId,
      negentropy: negentropy,
      filter: filter,
      onResult: onResult,
      onError: onError,
    );

    _sessions[subscriptionId] = session;

    // Send NEG-OPEN message
    final openMessage = NegOpenMessage(
      subscriptionId: subscriptionId,
      filter: filter,
      initialMessage: initialMessage.toHex(),
    );

    _sendMessage(openMessage.toJson());

    return subscriptionId;
  }

  /// Handles incoming message from relay
  void handleMessage(String messageJson) {
    try {
      final json = jsonDecode(messageJson);
      if (json is! List) {
        throw FormatException('Message must be JSON array');
      }

      final message = Nip77MessageParser.parse(json);

      if (message is NegMsgMessage) {
        _handleNegMsg(message);
      } else if (message is NegErrMessage) {
        _handleNegErr(message);
      }
    } catch (e) {
      // Invalid message format, ignore
    }
  }

  /// Handles NOTICE errors from relay (e.g., negentropy disabled)
  void handleNoticeError(String notice) {
    // Close all sessions with this error
    final sessionIds = List<String>.from(_sessions.keys);
    for (final id in sessionIds) {
      final session = _sessions[id];
      if (session?.onError != null) {
        session!.onError!('Relay error: $notice');
      }
      _sessions.remove(id);
    }
  }

  /// Closes a sync session
  void closeSync(String subscriptionId) {
    if (!_sessions.containsKey(subscriptionId)) {
      return;
    }

    final closeMessage = NegCloseMessage(subscriptionId: subscriptionId);
    _sendMessage(closeMessage.toJson());

    _sessions.remove(subscriptionId);
  }

  /// Closes all active sync sessions
  void closeAll() {
    final sessionIds = List<String>.from(_sessions.keys);
    for (final id in sessionIds) {
      closeSync(id);
    }
  }

  void _handleNegMsg(NegMsgMessage message) {
    final session = _sessions[message.subscriptionId];
    if (session == null) return;

    try {
      // Decode hex message
      final msgBytes = message.message.fromHex();

      // Process with Negentropy
      final response = session.negentropy.reconcile(msgBytes);

      if (response != null) {
        // Send response
        final responseMessage = NegMsgMessage(
          subscriptionId: message.subscriptionId,
          message: response.toHex(),
        );
        _sendMessage(responseMessage.toJson());
      } else {
        // Reconciliation complete
        final result = session.negentropy.getResult();
        if (result != null && session.onResult != null) {
          session.onResult!(result);
        }

        // Close session
        closeSync(message.subscriptionId);
      }
    } catch (e) {
      if (session.onError != null) {
        session.onError!('Error processing message: $e');
      }
      closeSync(message.subscriptionId);
    }
  }

  void _handleNegErr(NegErrMessage message) {
    final session = _sessions[message.subscriptionId];
    if (session == null) return;

    if (session.onError != null) {
      session.onError!('${message.errorCode}: ${message.details ?? ""}');
    }

    closeSync(message.subscriptionId);
  }

  /// Gets active session count
  int get activeSessionCount => _sessions.length;

  /// Gets list of active subscription IDs
  List<String> get activeSubscriptions => _sessions.keys.toList();
}

class _SyncSession {
  final String subscriptionId;
  final Negentropy negentropy;
  final Map<String, dynamic> filter;
  final SyncResultCallback? onResult;
  final ErrorCallback? onError;

  _SyncSession({
    required this.subscriptionId,
    required this.negentropy,
    required this.filter,
    this.onResult,
    this.onError,
  });
}
