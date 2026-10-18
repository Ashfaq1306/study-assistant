import '../../../core/network/api_client.dart';
import '../../auth/domain/app_user.dart';

class PairingCode {
  const PairingCode({required this.code, required this.qrPayload, required this.expiresAt});

  /// Readable form, e.g. "7KQ2-M9XD", for typing by hand.
  final String code;

  /// What the QR encodes: `studyassistant://pair?code=...`.
  final String qrPayload;
  final DateTime expiresAt;

  factory PairingCode.fromJson(Json json) => PairingCode(
    code: json['code']! as String,
    qrPayload: json['qrPayload']! as String,
    expiresAt: DateTime.parse(json['expiresAt']! as String),
  );
}

class FamilyLink {
  const FamilyLink({
    required this.id,
    required this.linkedAt,
    required this.personId,
    required this.personName,
    required this.personRole,
    required this.personAge,
  });

  final String id;
  final DateTime linkedAt;
  final String personId;
  final String personName;
  final UserRole personRole;
  final int personAge;

  factory FamilyLink.fromJson(Json json) {
    final person = json['person']! as Map<String, Object?>;
    return FamilyLink(
      id: json['id']! as String,
      linkedAt: DateTime.parse(json['linkedAt']! as String),
      personId: person['id']! as String,
      personName: person['name']! as String,
      personRole: UserRole.fromApi(person['role']! as String),
      personAge: (person['age']! as num).toInt(),
    );
  }
}

/// Server endpoints under /v1/family.
class FamilyApi {
  const FamilyApi(this._client);

  final ApiClient _client;

  Future<PairingCode> createPairingCode() async => PairingCode.fromJson(await _client.post('/v1/family/pairing-code'));

  Future<FamilyLink> link(String code) async =>
      FamilyLink.fromJson(await _client.post('/v1/family/links', data: {'code': code}));

  Future<List<FamilyLink>> links() async {
    final json = await _client.get('/v1/family/links');
    return [for (final item in json['links']! as List<Object?>) FamilyLink.fromJson(item! as Map<String, Object?>)];
  }

  Future<void> unlink(String linkId) => _client.delete('/v1/family/links/$linkId');
}
