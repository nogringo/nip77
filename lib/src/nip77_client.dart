import 'dart:async';
import 'dart:convert';
import 'nostr_relay.dart';
import 'negentropy_record.dart';
import 'sync_client.dart';

/// Complete NIP-77 client with WebSocket management
class Nip77Client {
  final NostrRelay relay;
  late final Nip77SyncClient _syncClient;
  StreamSubscription? _messageSubscription;

  Nip77Client({required String relayUrl}) : relay = NostrRelay(relayUrl) {
    _syncClient = Nip77SyncClient(
      sendMessage: (message) => relay.send(message),
    );
  }

  /// Connects to the relay
  Future<void> connect() async {
    await relay.connect();

    // Listen for messages and route to sync client
    _messageSubscription = relay.messages.listen((message) {
      final messageType = message[0] as String;

      // Handle NIP-77 messages
      if (messageType == 'NEG-MSG' || messageType == 'NEG-ERR') {
        _syncClient.handleMessage(jsonEncode(message));
      } else if (messageType == 'NOTICE') {
        // Check if NOTICE contains NIP-77 related errors
        if (message.length > 1) {
          final notice = message[1] as String;
          if (notice.toLowerCase().contains('negentropy')) {
            _syncClient.handleNoticeError(notice);
          }
        }
      }
    });
  }

  /// Syncs events and returns missing event IDs
  ///
  /// [myEvents] - Map of event IDs to timestamps {"eventId": timestamp}
  /// [filter] - Nostr filter to apply for the sync
  /// [timeout] - Maximum time to wait for sync completion (default: 30 seconds)
  Future<SyncResult> syncEvents({
    required Map<String, int> myEvents,
    required Map<String, dynamic> filter,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!relay.isConnected) {
      throw StateError('Not connected to relay. Call connect() first.');
    }

    final completer = Completer<SyncResult>();

    // Convert event map to records
    final records = myEvents.entries.map((entry) {
      return NegentropyRecord.fromHex(entry.value, entry.key);
    }).toList();

    // Start sync
    final subscriptionId = _syncClient.startSync(
      records: records,
      filter: filter,
      onResult: (result) {
        if (!completer.isCompleted) {
          completer.complete(
            SyncResult(needIds: result.needIds, haveIds: result.haveIds),
          );
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Sync error: $error'));
        }
      },
    );

    // Add timeout
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _syncClient.closeSync(subscriptionId);
        throw TimeoutException(
          'Sync timed out after ${timeout.inSeconds} seconds. '
          'The relay may not support NIP-77 or is not responding.',
          timeout,
        );
      },
    );
  }

  /// Syncs and fetches the actual missing events
  ///
  /// [myEvents] - Map of event IDs to timestamps {"eventId": timestamp}
  /// [filter] - Nostr filter to apply for the sync
  Future<List<Map<String, dynamic>>> syncAndFetchEvents({
    required Map<String, int> myEvents,
    required Map<String, dynamic> filter,
  }) async {
    // Step 1: Sync to get missing IDs
    final syncResult = await syncEvents(myEvents: myEvents, filter: filter);

    if (syncResult.needIds.isEmpty) {
      return []; // No new events
    }

    // Step 2: Fetch missing events
    return await fetchEventsByIds(syncResult.needIds);
  }

  /// Fetches events by their IDs using standard Nostr REQ
  Future<List<Map<String, dynamic>>> fetchEventsByIds(List<String> ids) async {
    if (!relay.isConnected) {
      throw StateError('Not connected to relay');
    }

    if (ids.isEmpty) return [];

    final completer = Completer<List<Map<String, dynamic>>>();
    final events = <Map<String, dynamic>>[];
    final subId = 'fetch_${DateTime.now().millisecondsSinceEpoch}';

    // Listen for responses
    StreamSubscription? subscription;
    subscription = relay.messages.listen((message) {
      final messageType = message[0] as String;

      if (messageType == 'EVENT' && message[1] == subId) {
        events.add(message[2] as Map<String, dynamic>);
      } else if (messageType == 'EOSE' && message[1] == subId) {
        // End of stored events
        subscription?.cancel();
        relay.sendClose(subId);
        completer.complete(events);
      }
    });

    // Send REQ
    relay.sendReq(subId, {'ids': ids});

    // Timeout after 30 seconds
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        subscription?.cancel();
        relay.sendClose(subId);
        return events; // Return what we got
      },
    );
  }

  /// Publishes an event to the relay
  Future<PublishResult> publishEvent(Map<String, dynamic> event) async {
    if (!relay.isConnected) {
      throw StateError('Not connected to relay');
    }

    final completer = Completer<PublishResult>();
    final eventId = event['id'] as String;

    // Listen for OK response
    StreamSubscription? subscription;
    subscription = relay.messages.listen((message) {
      if (message[0] == 'OK' && message[1] == eventId) {
        subscription?.cancel();
        final accepted = message[2] as bool;
        final reason = message.length > 3 ? message[3] as String : '';
        completer.complete(PublishResult(accepted: accepted, message: reason));
      }
    });

    relay.sendEvent(event);

    // Timeout after 10 seconds
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        subscription?.cancel();
        return PublishResult(accepted: false, message: 'Timeout');
      },
    );
  }

  /// Closes all active sync sessions
  void closeAllSyncs() {
    _syncClient.closeAll();
  }

  /// Disconnects from the relay
  Future<void> disconnect() async {
    closeAllSyncs();
    await _messageSubscription?.cancel();
    await relay.close();
  }

  /// Gets the number of active sync sessions
  int get activeSyncCount => _syncClient.activeSessionCount;

  /// Gets list of active subscription IDs
  List<String> get activeSubscriptions => _syncClient.activeSubscriptions;
}

/// Result of a sync operation
class SyncResult {
  /// Event IDs that we need (we don't have but relay does)
  final List<String> needIds;

  /// Event IDs that we have (relay doesn't have)
  final List<String> haveIds;

  SyncResult({required this.needIds, required this.haveIds});

  @override
  String toString() =>
      'SyncResult(need: ${needIds.length}, have: ${haveIds.length})';
}

/// Result of publishing an event
class PublishResult {
  final bool accepted;
  final String message;

  PublishResult({required this.accepted, required this.message});

  @override
  String toString() => 'PublishResult(accepted: $accepted, message: $message)';
}
