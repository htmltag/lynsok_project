import 'package:flutter_test/flutter_test.dart';
import 'package:desktop/models/index_model.dart';

void main() {
  group('IndexModel', () {
    test('toMap and fromMap round-trip configured ports', () {
      final createdAt = DateTime.parse('2026-04-03T12:00:00.000Z');
      final lastIndexedAt = DateTime.parse('2026-04-03T13:00:00.000Z');
      final model = IndexModel(
        id: 7,
        name: 'Test',
        sourcePath: '/src',
        lynPath: '/tmp/test.lyn',
        indexPath: '/tmp/test.idx',
        fileCount: 12,
        totalSize: 4096,
        createdAt: createdAt,
        lastIndexedAt: lastIndexedAt,
        serverActive: true,
        excludePatterns: const ['*.tmp', '*.bak'],
        httpServerPid: 111,
        mcpServerPid: 222,
        httpPort: 8181,
        mcpPort: 9191,
      );

      final map = model.toMap();
      expect(map['httpPort'], 8181);
      expect(map['mcpPort'], 9191);

      final hydrated = IndexModel.fromMap(map);
      expect(hydrated.httpPort, 8181);
      expect(hydrated.mcpPort, 9191);
      expect(hydrated.excludePatterns, ['*.tmp', '*.bak']);
      expect(hydrated.serverActive, true);
    });

    test('empty configured ports remain null after round-trip', () {
      final model = IndexModel(
        name: 'No Ports',
        sourcePath: '/src',
        lynPath: '/tmp/no-ports.lyn',
        indexPath: '/tmp/no-ports.idx',
      );

      final hydrated = IndexModel.fromMap(model.toMap());
      expect(hydrated.httpPort, isNull);
      expect(hydrated.mcpPort, isNull);
    });

    test('copyWith updates configured ports', () {
      final model = IndexModel(
        name: 'Copy',
        sourcePath: '/src',
        lynPath: '/tmp/copy.lyn',
        indexPath: '/tmp/copy.idx',
        httpPort: 8080,
        mcpPort: 9090,
      );

      final updated = model.copyWith(httpPort: 8181, mcpPort: 9191);
      expect(updated.httpPort, 8181);
      expect(updated.mcpPort, 9191);
    });

    test('copyWith can clear configured ports', () {
      final model = IndexModel(
        name: 'Copy',
        sourcePath: '/src',
        lynPath: '/tmp/copy.lyn',
        indexPath: '/tmp/copy.idx',
        httpPort: 8080,
        mcpPort: 9090,
      );

      final updated = model.copyWith(httpPort: null, mcpPort: null);
      expect(updated.httpPort, isNull);
      expect(updated.mcpPort, isNull);
    });

    test('formattedSize formats bytes correctly', () {
      final model = IndexModel(
        name: 'test',
        sourcePath: '/test/path',
        lynPath: '/tmp/a.lyn',
        indexPath: '/tmp/a.idx',
        totalSize: 1024,
      );

      expect(model.formattedSize, '1.0 KB');
    });

    test('formattedFileCount formats numbers correctly', () {
      final model = IndexModel(
        name: 'test',
        sourcePath: '/test/path',
        lynPath: '/tmp/a.lyn',
        indexPath: '/tmp/a.idx',
        fileCount: 1500,
      );

      expect(model.formattedFileCount, '1.5K');
    });

    test('formattedLastModified shows relative time', () {
      final now = DateTime.now();
      final model = IndexModel(
        name: 'test',
        sourcePath: '/test/path',
        lynPath: '/tmp/a.lyn',
        indexPath: '/tmp/a.idx',
        fileCount: 100,
        createdAt: now,
        lastIndexedAt: now.subtract(const Duration(hours: 2)),
      );

      expect(model.formattedLastModified, '2h ago');
    });

    test('isServerRunning mirrors serverActive', () {
      final model = IndexModel(
        name: 'test',
        sourcePath: '/test/path',
        lynPath: '/tmp/a.lyn',
        indexPath: '/tmp/a.idx',
        serverActive: true,
      );
      expect(model.isServerRunning, true);
    });
  });
}
