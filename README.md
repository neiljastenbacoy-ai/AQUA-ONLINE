# AQUARUN

Customer, rider and admin app for a water refilling station, with real map
tracking (OpenStreetMap, free, no API key).

## Live map tracking

- **Customers** drop a pin on the map when saving an address ("Set pin on map"),
  then watch the rider move toward that pin on the **Track Delivery** screen.
- **Riders** see every delivery stop pinned on a real map (**View Map Route**)
  plus their own GPS position, and broadcast their GPS to Firebase while signed in.
- **Admin** sets the station pin in Settings → Business Details ("Set station pin
  on map") — delivery routes start from there.

### Two tracking modes

| Mode | When | Rider marker source |
|---|---|---|
| **ESTIMATED** | Firebase not configured yet | Simulated — travels from station to pin as the order progresses |
| **LIVE GPS** | Firebase configured | The rider phone's real GPS, streamed through Firestore |

The app works fully in ESTIMATED mode out of the box — nothing to set up.

## Enabling real Firebase tracking (free)

1. Create a project at https://console.firebase.google.com (~2 minutes, free).
2. **Web app**: Project settings → Your apps → Web (`</>`) → copy the config
   values into `lib/firebase_config.dart` (replace the `PASTE_YOUR_...` placeholders).
3. **Android app**: register an Android app with package id `com.example.aqua`,
   download `google-services.json`, and put it in `android/app/`.
   (Or run `flutterfire configure` after `dart pub global activate flutterfire_cli`.)
4. In the Firebase console enable **Firestore Database** (start in *test mode*
   while developing).
5. Rebuild. The track screen badge switches from ESTIMATED to LIVE GPS.

Firestore layout: `riders/{riderId}` → `{ lat, lng, ts, orderId }`, written every
5 seconds by the rider device (see `lib/firebase_boot.dart`).

> Note: in this version the rider broadcasts GPS while the app is open. Keeping
> it alive in the background on Android needs a foreground service — a possible
> later addition.

## Smaller Android debug APK

Build an arm64-only debug APK with:

```powershell
flutter build apk --debug --target-platform android-arm64
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`. It is intended
for arm64 Android devices and will not run on x86_64 emulators.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
