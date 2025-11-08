import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Manages WebSocket connection to a Nostr relay
class NostrRelay {
  final String url;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final StreamController<List<dynamic>> _messageController =
      StreamController<List<dynamic>>.broadcast();

  bool _isConnected = false;

  NostrRelay(this.url);

  /// Stream of incoming messages from the relay
  Stream<List<dynamic>> get messages => _messageController.stream;

  /// Whether the connection is active
  bool get isConnected => _isConnected;

  /// Connects to the relay
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _subscription = _channel!.stream.listen(
        (data) {
          try {
            final message = jsonDecode(data as String);
            if (message is List) {
              _messageController.add(message);
            }
          } catch (e) {
            // Invalid JSON, ignore
          }
        },
        onError: (error) {
          _isConnected = false;
          _messageController.addError(error);
        },
        onDone: () {
          _isConnected = false;
        },
      );

      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  /// Sends a message to the relay
  void send(List<dynamic> message) {
    if (!_isConnected || _channel == null) {
      throw StateError('Not connected to relay');
    }
    _channel!.sink.add(jsonEncode(message));
  }

  /// Sends a REQ message
  void sendReq(String subscriptionId, Map<String, dynamic> filter) {
    send(['REQ', subscriptionId, filter]);
  }

  /// Sends an EVENT message
  void sendEvent(Map<String, dynamic> event) {
    send(['EVENT', event]);
  }

  /// Sends a CLOSE message
  void sendClose(String subscriptionId) {
    send(['CLOSE', subscriptionId]);
  }

  /// Closes the connection
  Future<void> close() async {
    _isConnected = false;
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _messageController.close();
  }
}
