import 'package:ndk/ndk.dart';
import 'package:nip77/nip77.dart';
import 'package:test/test.dart';

final relayUrl = 'wss://nostr-01.uid.ovh';

final relayEvents = [
  {
    "id": "c69b44aab38414727b58836ca6505f9a930ded45b647e39afb22edf39c882d2c",
    "pubkey":
        "af9750228b6eff2e7ded8714bf58da1dedc8ac7ba3050bb0177ff35c50c3c772",
    "created_at": 1762612866,
    "kind": 1,
    "tags": [],
    "content": "1",
    "sig":
        "a67bf2810b2c44e0c7a9fc2eb78b7ec7a45454e4b1ca3ac382ccd5c7414fde423c7ed00f94ab0c4945bc1dd845ec9c747da2bf7130656b0ec013c953c8e0e0c4",
  },
  {
    "id": "30d336a06f7e379bde76853e98759875cb11c0a1fe6040adc72baa27d5b7ddc8",
    "pubkey":
        "af9750228b6eff2e7ded8714bf58da1dedc8ac7ba3050bb0177ff35c50c3c772",
    "created_at": 1762612978,
    "kind": 1,
    "tags": [],
    "content": "2",
    "sig":
        "7d547ae1585c28cef447c48044792cf2a9525d37feb3e5b9308731f2606718ddce11e20f3215019efca9158c872739f0ac586c13353c056e96b9d242b3af5e84",
  },
  {
    "id": "fbe13a3fc3c3e5d0cde2309b8ab4ebdc98dc64b1013361a549771449b415cc82",
    "pubkey":
        "af9750228b6eff2e7ded8714bf58da1dedc8ac7ba3050bb0177ff35c50c3c772",
    "created_at": 1762612978,
    "kind": 1,
    "tags": [],
    "content": "3",
    "sig":
        "509e9803e00d5b07a41938a5c11410afc9ac70f363f8e801dbd7cb6056c136609923c4e30597c98d9c98dd4679afba08d6294bef42c867d396bdc8699db9f0c9",
  },
].map((e) => Nip01Event.fromJson(e)).toList();

void main() {
  test('Sync with no events', () async {
    await initRelay();

    final client = Nip77Client(relayUrl: relayUrl);

    await client.connect();

    final filter = {
      'kinds': [1],
      'authors': [
        'af9750228b6eff2e7ded8714bf58da1dedc8ac7ba3050bb0177ff35c50c3c772',
      ],
    };

    Map<String, int> myEvents = {};

    final syncResult = await client.syncEvents(
      myEvents: myEvents,
      filter: filter,
    );

    expect(syncResult.needIds.length, equals(relayEvents.length));
    expect(syncResult.haveIds.length, equals(0));

    await client.disconnect();
  });

  test('Sync with events', () async {
    await initRelay();

    final client = Nip77Client(relayUrl: relayUrl);

    await client.connect();

    final filter = {
      'kinds': [1],
      'authors': [
        'af9750228b6eff2e7ded8714bf58da1dedc8ac7ba3050bb0177ff35c50c3c772',
      ],
    };

    Map<String, int> myEvents = Map.fromEntries([
      MapEntry(relayEvents.first.id, relayEvents.first.createdAt),
    ]);

    final syncResult = await client.syncEvents(
      myEvents: myEvents,
      filter: filter,
    );

    expect(
      syncResult.needIds.length,
      equals(relayEvents.length - myEvents.length),
    );
    expect(syncResult.haveIds.length, equals(0));

    await client.disconnect();
  });

  test('Sync with 1 more event', () async {
    await initRelay();

    final client = Nip77Client(relayUrl: relayUrl);

    await client.connect();

    final filter = {
      'kinds': [1],
      'authors': [
        'af9750228b6eff2e7ded8714bf58da1dedc8ac7ba3050bb0177ff35c50c3c772',
      ],
    };

    Map<String, int> myEvents = Map.fromEntries([
      MapEntry(
        "c69b44aab38414727b58836ca6505f9a930ded45b647e39afb22edf39c882d2d",
        relayEvents.first.createdAt,
      ),
    ]);

    final syncResult = await client.syncEvents(
      myEvents: myEvents,
      filter: filter,
    );

    expect(syncResult.needIds.length, equals(relayEvents.length));
    expect(syncResult.haveIds.length, equals(1));

    await client.disconnect();
  });

  test('Sync with all events localy', () async {
    await initRelay();

    final client = Nip77Client(relayUrl: relayUrl);

    await client.connect();

    final filter = {
      'kinds': [1],
      'authors': [
        'af9750228b6eff2e7ded8714bf58da1dedc8ac7ba3050bb0177ff35c50c3c772',
      ],
    };

    Map<String, int> myEvents = Map.fromEntries(
      relayEvents.map((e) => MapEntry(e.id, e.createdAt)),
    );

    final syncResult = await client.syncEvents(
      myEvents: myEvents,
      filter: filter,
    );

    expect(syncResult.needIds.length, equals(0));
    expect(syncResult.haveIds.length, equals(0));

    await client.disconnect();
  });
}

Future<void> initRelay() async {
  final ndk = Ndk(
    NdkConfig(
      eventVerifier: Bip340EventVerifier(),
      cache: MemCacheManager(),
      bootstrapRelays: [relayUrl],
    ),
  );

  for (var event in relayEvents) {
    final broadcast = ndk.broadcast.broadcast(nostrEvent: event);
    await broadcast.broadcastDoneFuture;
  }

  await ndk.destroy();
}
