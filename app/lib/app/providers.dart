import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/server_clock.dart';
import '../core/storage/token_store.dart';
import '../features/auth/data/auth_api.dart';
import '../features/exam/data/exam_api.dart';
import '../features/family/data/family_api.dart';
import '../features/study/data/study_api.dart';

/// App-wide dependencies. Tests override these with fakes.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(baseUrl: AppConfig.apiBaseUrl, store: ref.watch(tokenStoreProvider)),
);

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));

final familyApiProvider = Provider<FamilyApi>((ref) => FamilyApi(ref.watch(apiClientProvider)));

final studyApiProvider = Provider<StudyApi>((ref) => StudyApi(ref.watch(apiClientProvider)));

final serverClockProvider = Provider<ServerClock>((ref) => ref.watch(apiClientProvider).clock);

final examApiProvider = Provider<ExamApi>((ref) => ExamApi(ref.watch(apiClientProvider)));
