# Study Assistant: Flutter app

See the [main README](../README.md) for setup. Quick start:

```bash
flutter pub get
adb reverse tcp:8080 tcp:8080   # reach the local API from the phone or emulator
flutter run
```

Point at another API with `--dart-define=API_BASE_URL=https://api.example.com`.
