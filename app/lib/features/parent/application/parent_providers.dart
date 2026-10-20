import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/parent_api.dart';
import '../domain/parent_models.dart';

final parentApiProvider = Provider<ParentApi>((ref) => ParentApi(ref.watch(apiClientProvider)));

/// Each linked child with today at a glance.
final childrenProvider = FutureProvider.autoDispose<List<ChildSummary>>(
  (ref) => ref.watch(parentApiProvider).children(),
);

/// One child's study, screen time, exams, locks and phones.
final childDetailProvider = FutureProvider.autoDispose.family<ChildDetail, String>(
  (ref, id) => ref.watch(parentApiProvider).child(id),
);

final questionSetsProvider = FutureProvider.autoDispose<List<QuestionSet>>(
  (ref) => ref.watch(parentApiProvider).questionSets(),
);

final notificationsProvider = FutureProvider.autoDispose<({List<AppNotification> items, int unread})>(
  (ref) => ref.watch(parentApiProvider).notifications(),
);
