import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/config/remote_config.dart';

Map<String, Object?> config([Map<String, Object?> extra = const {}]) => {
  'subjects': ['Mathematics'],
  'minPassPercent': 50,
  'minStudyMinutes': 5,
  'maxStudyMinutes': 240,
  'earlyFinishPercent': 50,
  'maxQuestions': 30,
  'examRetryCooldownSeconds': 0,
  ...extra,
};

void main() {
  test('a server without SMS offers codes by email only', () {
    final c = RemoteConfig.fromJson(
      config({
        'otpChannels': ['EMAIL'],
      }),
    );
    expect(c.emailCodes, isTrue);
    expect(c.smsCodes, isFalse);
  });

  test('an older server that does not say is assumed to offer both', () {
    final c = RemoteConfig.fromJson(config());
    expect(c.emailCodes && c.smsCodes, isTrue);
  });
}
