/// Build-time configuration, set with `--dart-define`.
///
/// During development the phone reaches the API on your computer through
/// `adb reverse tcp:8080 tcp:8080`, so the default works for both a USB phone
/// and the emulator. Release builds must pass an HTTPS URL:
/// `flutter build apk --dart-define=API_BASE_URL=https://api.example.com`.
abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8080');

  static const appName = 'Study Assistant';

  /// Keep in step with the version in pubspec.yaml.
  static const appVersion = '0.4.3';

  /// Test builds are published as GitHub Releases here (tags like v0.4.0-b4).
  static const updateRepo = 'Ashfaq1306/study-assistant';

  /// Must match PARENTAL_CONTROL_AGE on the server.
  static const parentalControlAge = 15;
}
