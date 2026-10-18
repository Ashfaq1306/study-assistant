import 'package:study_assistant/features/auth/domain/app_user.dart';

AppUser testUser({
  UserRole role = UserRole.student,
  int age = 16,
  bool parentalControlRequired = false,
  int linkedParents = 0,
  int linkedChildren = 0,
  String name = 'Nadia Rahman',
}) => AppUser(
  id: 'u1',
  role: role,
  name: name,
  email: 'nadia@example.com',
  dateOfBirth: '2010-01-15',
  age: age,
  parentalControlRequired: parentalControlRequired,
  linkedParents: linkedParents,
  linkedChildren: linkedChildren,
);
