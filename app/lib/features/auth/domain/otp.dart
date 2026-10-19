enum OtpChannel {
  email,
  sms;

  static OtpChannel fromApi(String value) => value == 'SMS' ? OtpChannel.sms : OtpChannel.email;

  String get api => name.toUpperCase();
  String get label => this == OtpChannel.email ? 'Email' : 'SMS';
}

/// Where a one-time code went and when another may be requested.
class OtpDelivery {
  const OtpDelivery({required this.channel, required this.destination, required this.resendAvailableAt, this.devCode});

  final OtpChannel channel;

  /// Masked, e.g. "na•••@example.com".
  final String destination;
  final DateTime resendAvailableAt;

  /// Only sent by a development server, so testing needs no email or SMS.
  final String? devCode;

  factory OtpDelivery.fromJson(Map<String, Object?> json) => OtpDelivery(
    channel: OtpChannel.fromApi(json['channel']! as String),
    destination: json['destination']! as String,
    resendAvailableAt: DateTime.parse(json['resendAvailableAt']! as String),
    devCode: json['devCode'] as String?,
  );
}

/// An account that exists but still needs its code entered.
class PendingVerification {
  const PendingVerification({
    required this.userId,
    required this.channel,
    this.delivery,
    this.otherChannelAvailable = false,
  });

  final String userId;
  final OtpChannel channel;

  /// Null when no new code was sent (e.g. the resend cooldown was active).
  final OtpDelivery? delivery;

  /// Whether the user can switch to receiving the code the other way.
  final bool otherChannelAvailable;
}
