enum UserRole {
  student,
  parent,
  admin;

  static UserRole fromApi(String value) => switch (value) {
    'PARENT' => UserRole.parent,
    'ADMIN' => UserRole.admin,
    _ => UserRole.student,
  };

  String get api => name.toUpperCase();
}

class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.name,
    required this.dateOfBirth,
    required this.age,
    this.email,
    this.phone,
    this.parentalControlRequired = false,
    this.linkedParents = 0,
    this.linkedChildren = 0,
  });

  final String id;
  final UserRole role;
  final String name;
  final String? email;
  final String? phone;
  final String dateOfBirth;
  final int age;
  final bool parentalControlRequired;
  final int linkedParents;
  final int linkedChildren;

  bool get isParent => role == UserRole.parent;

  /// Under-15 students stay on the "link a parent" screen until one links.
  bool get needsParentLink => role == UserRole.student && parentalControlRequired && linkedParents == 0;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  factory AppUser.fromJson(Map<String, Object?> json) {
    final parental = json['parentalControl'] as Map<String, Object?>?;
    return AppUser(
      id: json['id']! as String,
      role: UserRole.fromApi(json['role']! as String),
      name: json['name']! as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      dateOfBirth: json['dateOfBirth']! as String,
      age: (json['age']! as num).toInt(),
      parentalControlRequired: parental?['required'] as bool? ?? false,
      linkedParents: (parental?['linkedParents'] as num?)?.toInt() ?? 0,
      linkedChildren: (json['linkedChildren'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.api,
    'name': name,
    'email': email,
    'phone': phone,
    'dateOfBirth': dateOfBirth,
    'age': age,
    'parentalControl': role == UserRole.student
        ? {'required': parentalControlRequired, 'linkedParents': linkedParents}
        : null,
    'linkedChildren': role == UserRole.parent ? linkedChildren : null,
  };
}
