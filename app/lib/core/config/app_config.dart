/// Build-time configuration, set with `--dart-define`.
///
/// A server on a home computer can be reached from any network through a tunnel; its
/// address is looked up from [apiDiscoveryUrl] (see `ApiEndpoint`).
///
/// During development the phone reaches the API on your computer through
/// `adb reverse tcp:8080 tcp:8080`, so the default works for both a USB phone
/// and the emulator. Release builds must pass an HTTPS URL:
/// `flutter build apk --dart-define=API_BASE_URL=https://api.example.com`.
abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8080');

  /// A JSON file holding the API's current address (`{"apiBaseUrl": "https://…"}`), for a server whose
  /// address can change, like one on a home computer behind a tunnel (see scripts/serve-public.ps1).
  /// Empty: always use [apiBaseUrl].
  static const apiDiscoveryUrl = String.fromEnvironment('API_DISCOVERY_URL');

  static const appName = 'Study Mate';

  /// Keep in step with the version in pubspec.yaml.
  static const appVersion = '1.0.1';

  /// Test builds are published as GitHub Releases here (tags like v0.4.0-b4).
  static const updateRepo = 'Ashfaq1306/study-mate';

  /// Must match PARENTAL_CONTROL_AGE on the server.
  static const parentalControlAge = 15;
}
