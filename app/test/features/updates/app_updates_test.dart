import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/updates/app_updates.dart';

Map<String, Object?> _release(String tag, {bool draft = false, String asset = 'study-assistant.apk'}) => {
  'tag_name': tag,
  'draft': draft,
  'body': 'What is new',
  'assets': [
    {'name': asset, 'browser_download_url': 'https://example.com/$tag/$asset'},
  ],
};

void main() {
  test('reads version and build from release tags', () {
    expect(parseReleaseTag('v0.4.0-b4'), (version: '0.4.0', build: 4));
    expect(parseReleaseTag('0.10.2-b37'), (version: '0.10.2', build: 37));
    expect(parseReleaseTag('v0.4.0'), isNull);
    expect(parseReleaseTag('nightly'), isNull);
  });

  test('picks the newest build with an APK that is newer than this one', () {
    final update = newestUpdate([
      _release('v0.4.0-b4'),
      _release('v0.5.0-b6'),
      _release('v0.6.0-b7', draft: true),
      _release('v0.5.1-b8', asset: 'notes.txt'),
      _release('v0.4.1-b5'),
    ], 4);
    expect(update?.build, 6);
    expect(update?.version, '0.5.0');
    expect(update?.downloadUrl, 'https://example.com/v0.5.0-b6/study-assistant.apk');
  });

  test("picks the APK built for this phone's chip, never another chip's", () {
    final release = {
      'tag_name': 'v0.5.0-b9',
      'draft': false,
      'assets': [
        for (final abi in ['armeabi-v7a', 'arm64-v8a', 'x86_64'])
          {'name': 'study-assistant-0.5.0-b9-$abi.apk', 'browser_download_url': 'https://x/$abi.apk'},
      ],
    };
    expect(newestUpdate([release], 4, abi: 'arm64-v8a')?.downloadUrl, 'https://x/arm64-v8a.apk');
    expect(newestUpdate([release], 4, abi: 'riscv64'), isNull);
  });

  test('nothing to do when this build is the newest', () {
    expect(newestUpdate([_release('v0.4.0-b4')], 4), isNull);
    expect(newestUpdate([], 1), isNull);
  });
}
