import 'package:nip77/nip77.dart';

void main() async {
  final client = Nip77Client(relayUrl: "wss://nostr-01.uid.ovh");

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
}
