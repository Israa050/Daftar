# Testing, CI and CD

The test strategy, the manual integration test, and what runs on every pull
request. Extracted from the README to keep that file short for a first-time
visitor.

## Running the tests

```bash
flutter test
```

Two complementary approaches are used:

- **Drift-backed tests** (`database_test.dart`, `transactions_repository_test.dart`,
  `category_repository_test.dart`, `transactions_bloc_test.dart`,
  `sync/sync_queue_repository_impl_test.dart`, `widget_test.dart`)
  drive a real in-memory Drift database (`NativeDatabase.memory()`) instead of
  mocks, so no state leaks between tests and nothing touches disk.
- **Mocktail-backed bloc/cubit/use-case tests** (`transactions_bloc_mocktail_test.dart`,
  `categories_bloc_mocktail_test.dart`, `balance_cubit_mocktail_test.dart`,
  `connectivity/`, `sync/watch_pending_sync_count_usecase_test.dart`,
  `sync/sync_repository_impl_test.dart`, `sync/sync_data_usecase_test.dart`,
  `sync/sync_cubit_test.dart`)
  use [`bloc_test`](https://pub.dev/packages/bloc_test) and
  [`mocktail`](https://pub.dev/packages/mocktail) with mocked use cases
  ([`test/helpers/mocks.dart`](../test/helpers/mocks.dart)) to assert state
  emissions in isolation, including failure paths a real repository can't be
  forced into.
- **Pure-function tests** (`format_test.dart`,
  `backup/export_serializer_test.dart`) need neither a database nor mocks.

### What the sync tests cover specifically

- `sync/sync_repository_impl_test.dart` — `pushPending()`'s independent-row
  processing: one failing entry doesn't block the rest of that pass.
- `sync/sync_data_usecase_test.dart` — the push-then-pull sequencing (a push
  failure skips pull, a pull failure is returned, pull still runs when nothing
  was pushed).
- `sync/sync_cubit_test.dart` — `SyncCubit`'s states, the in-flight guard, and
  the `allFailed` inference against a mocked `SyncDataUseCase`.
- `sync/sync_repository_pull_test.dart` (real in-memory Drift) —
  `pullRemoteChanges()`: last-write-wins for transactions and categories
  (newer remote applied, tie and older remote keep local), the applied row
  carrying the remote `updatedAt`, a repeat pull applying nothing, pull never
  enqueueing, pull order against the foreign key, and the per-type watermark
  (saved, reused as `since`, not advanced when that type's pull fails).
- `sync/pull_conflict_test.dart` — a real conflict through the real
  `CategoryRepositoryImpl` (an offline edit, queued) against a mocked remote
  edit, checking which version the pull leaves in the local DB. A whole-sync
  test there also runs the real push-then-pull against a fake server that
  follows the push functions' rule (write only if not newer) and checks that
  both sides end on the later edit.
- `sync/supabase_sync_data_source_test.dart` — the local→remote payload
  mapping (`camelCase` → `snake_case`, `user_id` stamping) and the choice of
  Postgres function and `p_`-prefixed arguments (`rpcCallFor`), tested
  directly rather than by mocking `pushEntry()`'s Supabase SDK calls
  end-to-end: the SDK's `client.rpc(...)` / `client.from(...)` chains get
  their awaitability from an overridden generic `then` method that `mocktail`
  can't reliably intercept.

## Integration test (run by hand)

[`integration_test/offline_sync_test.dart`](../integration_test/offline_sync_test.dart)
runs the real app on a device or emulator and proves what the unit tests
can't: that the pieces are wired together. A transaction added while offline
is saved, queued and shown as pending (the badge reads `1`) with nothing
pushed; once the connection returns, the change is pushed and the badge
clears.

Only the two edges are faked, swapped in through GetIt: the connectivity
source (`integration_test/fakes/fake_connectivity_repository.dart`) and the
sync remote (`integration_test/fakes/fake_sync_remote.dart`, which records
what is pushed). The blocs, the repositories and an in-memory Drift database
are real. It never touches the real Supabase project, so it needs no secrets.

```bash
flutter devices                                                  # find the device id
flutter test integration_test/offline_sync_test.dart -d <device-id>
```

The first run builds a debug APK and takes a few minutes; later runs take
about a minute. Keep the phone unlocked while it runs.

## Continuous integration

Every pull request into `main` runs
[`.github/workflows/flutter-test.yml`](../.github/workflows/flutter-test.yml):
dependency install → Drift code generation → `dart format` check →
`flutter analyze` → `flutter test`. A PR can't merge with a formatting
issue, an analyzer warning, or a failing test.

**The integration test is not part of CI; it stays manual for now.**
`flutter test` on a plain Linux runner has no device to run it on. Adding one
means booting an Android emulator (which needs hardware acceleration set up
on the runner) or building the Linux desktop target under a virtual display,
which adds minutes to every pull request and is a common source of flaky
failures. The unit tests already run on every PR, and the integration test
covers wiring that changes rarely, so the cost is not worth it yet. Nothing
blocks adding it later: it needs no secrets, because the remote is faked.

Run it by hand before tagging a release, and after changing sync,
connectivity or the service locator. If it is automated, the likely first
step is a Linux desktop job (`flutter test integration_test -d linux` under
`xvfb`); the repo already has a `linux/` target.

## Continuous deployment

Pushing to the `production` branch runs
[`.github/workflows/deploy-production.yml`](../.github/workflows/deploy-production.yml):
it builds a signed, arm64-only release APK and uploads it to Firebase App
Distribution's `internal` tester group. `production` is a deploy-only
branch, separate from `main`. Full setup steps, the release-signing
approach, and troubleshooting notes are in
[`firebase-app-distribution.md`](firebase-app-distribution.md).
