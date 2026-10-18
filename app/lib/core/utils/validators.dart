/// Client-side checks that mirror the server rules, so mistakes show up
/// before a round trip. The server stays the source of truth.
abstract final class Validators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final _banglaDigits = RegExp('[০-৯]');

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return 'Enter your name.';
    if (v.length > 60) return 'Use at most 60 characters.';
    return null;
  }

  static String? email(String? value, {bool required = true}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? 'Enter your email.' : null;
    return _email.hasMatch(v) ? null : 'Enter a valid email address.';
  }

  static String? phone(String? value, {bool required = true}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? 'Enter your mobile number.' : null;
    return normalizePhone(v) == null ? 'Enter a valid mobile number, e.g. 01712345678.' : null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.length < 8) return 'Use at least 8 characters.';
    if (v.length > 128) return 'Use at most 128 characters.';
    if (!RegExp('[A-Za-z]').hasMatch(v)) return 'Include at least one letter.';
    if (!RegExp(r'\d').hasMatch(v)) return 'Include at least one number.';
    return null;
  }

  static String? identifier(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email or mobile number.';
    if (v.contains('@')) return email(v);
    return phone(v);
  }

  static String? otp(String? value) =>
      RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '') ? null : 'Enter the 6-digit code.';

  /// Same rules as the server's normalizePhone: local Bangladeshi numbers get
  /// +880, anything else must be international.
  static String? normalizePhone(String input) {
    final cleaned = input
        .trim()
        .replaceAllMapped(_banglaDigits, (m) => '${m[0]!.codeUnitAt(0) - 0x09E6}')
        .replaceAll(RegExp(r'[\s\-().]'), '');
    if (RegExp(r'^01[3-9]\d{8}$').hasMatch(cleaned)) return '+88$cleaned';
    if (RegExp(r'^8801[3-9]\d{8}$').hasMatch(cleaned)) return '+$cleaned';
    if (RegExp(r'^00[1-9]\d{7,14}$').hasMatch(cleaned)) return '+${cleaned.substring(2)}';
    if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(cleaned)) return cleaned;
    return null;
  }
}

/// 0 = empty, 1 = weak, 2 = okay, 3 = strong. Only drives the meter.
int passwordStrength(String password) {
  if (password.isEmpty) return 0;
  var score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp('[A-Za-z]').hasMatch(password) && RegExp(r'\d').hasMatch(password)) score++;
  if (RegExp('[A-Z]').hasMatch(password) && RegExp('[a-z]').hasMatch(password)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
  return switch (score) {
    <= 2 => 1,
    3 => 2,
    _ => 3,
  };
}

/// Whole years old on [today].
int ageOn(DateTime dateOfBirth, DateTime today) {
  var age = today.year - dateOfBirth.year;
  if (today.month < dateOfBirth.month || (today.month == dateOfBirth.month && today.day < dateOfBirth.day)) {
    age--;
  }
  return age;
}
