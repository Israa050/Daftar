import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/features/backup/cubit/export_cubit.dart';
import 'package:stockflow/features/backup/domain/entities/exported_file.dart';
import 'package:stockflow/features/backup/domain/usecases/export_data_usecase.dart';

class _MockExportDataUseCase extends Mock implements ExportDataUseCase {}

final _file = ExportedFile(
  path: '/tmp/export.json',
  byteSize: 42,
  countsByKey: {'transactions': 2, 'categories': 1},
);

void main() {
  late _MockExportDataUseCase useCase;
  // Holds an export open, so a test can call export() while one is running.
  late Completer<Result<ExportedFile>> running;

  setUp(() {
    useCase = _MockExportDataUseCase();
    running = Completer<Result<ExportedFile>>();
  });

  ExportCubit build() => ExportCubit(exportDataUseCase: useCase);

  test('starts idle', () {
    expect(build().state, isA<ExportIdle>());
  });

  blocTest<ExportCubit, ExportState>(
    'emits in-progress, then success with the exported file',
    build: () {
      when(() => useCase()).thenAnswer((_) async => Success(_file));
      return build();
    },
    act: (cubit) => cubit.export(),
    expect: () => [
      isA<ExportInProgress>(),
      isA<ExportSuccess>().having((s) => s.file, 'file', same(_file)),
    ],
  );

  blocTest<ExportCubit, ExportState>(
    'emits in-progress, then failure with the message',
    build: () {
      when(
        () => useCase(),
      ).thenAnswer((_) async => const Failure<ExportedFile>('disk full'));
      return build();
    },
    act: (cubit) => cubit.export(),
    expect: () => [
      isA<ExportInProgress>(),
      isA<ExportFailure>().having((s) => s.message, 'message', 'disk full'),
    ],
  );

  blocTest<ExportCubit, ExportState>(
    'ignores a second export while one is running',
    build: () {
      when(() => useCase()).thenAnswer((_) => running.future);
      return build();
    },
    act: (cubit) async {
      final first = cubit.export();
      await cubit.export(); // ignored: the first is still in progress
      running.complete(Success(_file));
      await first;
    },
    expect: () => [isA<ExportInProgress>(), isA<ExportSuccess>()],
    verify: (_) => verify(() => useCase()).called(1),
  );
}
