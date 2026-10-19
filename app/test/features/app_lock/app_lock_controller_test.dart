import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_assistant/app/providers.dart';
import 'package:study_assistant/core/network/api_exception.dart';
import 'package:study_assistant/core/platform/app_lock_platform.dart';
import 'package:study_assistant/core/storage/token_store.dart';
import 'package:study_assistant/features/app_lock/application/app_lock_controller.dart';
import 'package:study_assistant/features/app_lock/data/device_api.dart';
import 'package:study_assistant/features/auth/data/auth_api.dart';

import '../../helpers.dart';

class MockPlatform extends Mock implements AppLockPlatform {}

class MockDeviceApi extends Mock implements DeviceApi {}

class MockAuthApi extends Mock implements AuthApi {}

const lockedState = DeviceLockState(
  locked: true,
  wholePhone: false,
  packages: ['com.google.android.youtube'],
  strict: true,
  reasons: [],
  raw: {'locked': true},
);

NativeLockStatus native({String? owner, String? token, bool locked = false, bool shortcutOn = false}) =>
    NativeLockStatus(
      protectionOn: true,
      usageAccess: false,
      deviceModel: 'Test Phone',
      locked: locked,
      shortcutOn: shortcutOn,
      ownerUserId: owner,
      deviceToken: token,
    );

void main() {
  late MockPlatform platform;
  late MockDeviceApi devices;
  late MockAuthApi auth;
  late MemoryTokenStore store;

  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  setUp(() async {
    platform = MockPlatform();
    devices = MockDeviceApi();
    auth = MockAuthApi();
    store = MemoryTokenStore();
    await store.save(accessToken: 'a', refreshToken: 'r');
    when(() => auth.me()).thenAnswer((_) async => testUser()); // student "u1"
    when(() => platform.isSupported).thenReturn(true);
    when(() => platform.installedApps(withIcons: false)).thenAnswer((_) async => const []);
    when(() => platform.applyState(any())).thenAnswer((_) async {});
    when(
      () => platform.configure(
        baseUrl: any(named: 'baseUrl'),
        deviceToken: any(named: 'deviceToken'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => devices.heartbeat(
        any(),
        protectionOn: any(named: 'protectionOn'),
        usageAccess: any(named: 'usageAccess'),
        shortcutOn: any(named: 'shortcutOn'),
        appVersion: any(named: 'appVersion'),
        installedApps: any(named: 'installedApps'),
      ),
    ).thenAnswer((_) async => lockedState);
  });

  Future<AppLockStatus> run() async {
    final container = ProviderContainer.test(
      overrides: [
        appLockPlatformProvider.overrideWithValue(platform),
        deviceApiProvider.overrideWithValue(devices),
        authApiProvider.overrideWithValue(auth),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    // Wait for sign-in to be restored, then for the app-lock sync.
    container.listen(appLockProvider, (_, _) {});
    for (var i = 0; i < 200; i++) {
      final s = container.read(appLockProvider);
      if (s.hasValue && (s.value!.registered || s.value!.lockedForAnotherUser)) return s.value!;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return container.read(appLockProvider).requireValue;
  }

  test('registers a new phone once and applies the server lock state', () async {
    var status = native();
    when(() => platform.status()).thenAnswer((_) async => status);
    when(
      () => devices.register(
        name: any(named: 'name'),
        appVersion: any(named: 'appVersion'),
      ),
    ).thenAnswer((_) async {
      status = native(owner: 'u1', token: 't1');
      return (deviceId: 'd1', deviceToken: 't1');
    });

    final result = await run();

    expect(result.registered, isTrue);
    expect(result.state.locked, isTrue);
    verify(
      () => devices.register(
        name: 'Test Phone',
        appVersion: any(named: 'appVersion'),
      ),
    ).called(1);
    verify(() => platform.applyState({'locked': true})).called(greaterThanOrEqualTo(1));
  });

  test("never takes over a phone while another account's lock is running", () async {
    when(() => platform.status()).thenAnswer((_) async => native(owner: 'someone-else', token: 'old', locked: true));
    when(() => devices.state('old')).thenAnswer((_) async => lockedState);

    final result = await run();

    expect(result.lockedForAnotherUser, isTrue);
    expect(result.registered, isFalse);
    verifyNever(
      () => devices.register(
        name: any(named: 'name'),
        appVersion: any(named: 'appVersion'),
      ),
    );
  });

  test('asks the server rather than trusting a stale cached lock', () async {
    var status = native(owner: 'someone-else', token: 'old', locked: true);
    when(() => platform.status()).thenAnswer((_) async => status);
    when(() => devices.state('old')).thenAnswer((_) async => DeviceLockState.unlocked);
    when(
      () => devices.register(
        name: any(named: 'name'),
        appVersion: any(named: 'appVersion'),
      ),
    ).thenAnswer((_) async {
      status = native(owner: 'u1', token: 't2');
      return (deviceId: 'd2', deviceToken: 't2');
    });

    final result = await run();

    expect(result.lockedForAnotherUser, isFalse);
    expect(result.registered, isTrue);
  });

  test('stays on the safe side when offline: an unknown lock counts as running', () async {
    when(() => platform.status()).thenAnswer((_) async => native(owner: 'someone-else', token: 'old', locked: true));
    when(() => devices.state('old')).thenThrow(const ApiException(code: ApiException.network, message: 'offline'));

    expect((await run()).lockedForAnotherUser, isTrue);
  });

  test('is not ready while an accessibility shortcut can switch the lock off', () async {
    when(() => platform.status()).thenAnswer((_) async => native(owner: 'u1', token: 't1', shortcutOn: true));

    final result = await run();

    expect(result.registered, isTrue);
    expect(result.shortcutOn, isTrue);
    expect(result.ready, isFalse);
  });
}
