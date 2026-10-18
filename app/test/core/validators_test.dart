import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/utils/validators.dart';

void main() {
  group('normalizePhone (mirrors the server)', () {
    const cases = {
      '01712345678': '+8801712345678',
      '017-1234-5678': '+8801712345678',
      '8801712345678': '+8801712345678',
      '০১৭১২৩৪৫৬৭৮': '+8801712345678',
      '00447911123456': '+447911123456',
      '+14155552671': '+14155552671',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(Validators.normalizePhone(input), expected));
    });

    for (final bad in ['', '12345', '01212345678', 'hello']) {
      test('rejects "$bad"', () => expect(Validators.normalizePhone(bad), isNull));
    }
  });

  test('password rules match the server', () {
    expect(Validators.password('short1'), isNotNull);
    expect(Validators.password('onlyletters'), isNotNull);
    expect(Validators.password('12345678'), isNotNull);
    expect(Validators.password('study1234'), isNull);
  });

  test('identifier accepts an email or a phone number', () {
    expect(Validators.identifier('nadia@example.com'), isNull);
    expect(Validators.identifier('01712345678'), isNull);
    expect(Validators.identifier('nadia@'), isNotNull);
    expect(Validators.identifier(''), isNotNull);
  });

  test('optional fields may be empty', () {
    expect(Validators.email('', required: false), isNull);
    expect(Validators.phone('  ', required: false), isNull);
    expect(Validators.email('', required: true), isNotNull);
  });

  test('ageOn counts whole years', () {
    final dob = DateTime(2011, 6, 2);
    expect(ageOn(dob, DateTime(2026, 6, 1)), 14);
    expect(ageOn(dob, DateTime(2026, 6, 2)), 15);
  });

  test('passwordStrength grows with variety and length', () {
    expect(passwordStrength(''), 0);
    expect(passwordStrength('abc'), 1);
    expect(passwordStrength('study1234'), 1);
    expect(passwordStrength('Study12345'), 2);
    expect(passwordStrength('Study-time-2026!'), 3);
  });
}
