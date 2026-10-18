import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/family_api.dart';

/// Linked parents (for a student) or children (for a parent).
final familyLinksProvider = FutureProvider.autoDispose<List<FamilyLink>>((ref) => ref.watch(familyApiProvider).links());
