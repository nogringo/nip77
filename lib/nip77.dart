/// NIP-77 Negentropy Protocol implementation for efficient Nostr event syncing.
///
/// This library provides a complete implementation of the NIP-77 protocol,
/// which uses Negentropy for efficient set reconciliation between clients and relays.
///
/// Main class to use: [Nip77Client] - handles WebSocket connection and syncing.
library;

// High-level API (recommended)
export 'src/nip77_client.dart';
export 'src/nostr_relay.dart';

// Core protocol implementation
export 'src/negentropy.dart';
export 'src/negentropy_record.dart';
export 'src/messages.dart';
export 'src/sync_client.dart';
export 'src/fingerprint.dart';
export 'src/varint.dart';
export 'src/accumulator.dart';
