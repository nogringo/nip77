Dart implementation of NIP-77 Negentropy Syncing.

## Features

- get the events ids that you have and the relay don't
- get the events ids that relay have and you don't

## Usage

```dart
final client = Nip77Client(relayUrl: "wss://relay.example.com");

await client.connect();

final filter = {
'kinds': [0],
};

Map<String, int> myEvents = {};

final syncResult = await client.syncEvents(
myEvents: myEvents,
filter: filter,
);

print("Events ids that we need ${syncResult.needIds}");
print("Events ids that we have and relay don't ${syncResult.haveIds}");

await client.disconnect();
```
