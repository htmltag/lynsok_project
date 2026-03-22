import 'package:flutter_test/flutter_test.dart';
import 'package:desktop/models/index_model.dart';

void main() {
  group('IndexModel', () {
    test('formattedSize formats bytes correctly', () {
      final model =
          IndexModel(name: '', sourcePath: '', lynPath: '', indexPath: '')
            ..name = 'test'
            ..sourcePath = '/test/path'
            ..fileCount = 100
            ..createdAt = DateTime.now()
            ..lastIndexedAt = DateTime.now();

      expect(model.formattedSize, '1.0 KB');
    });

    test('formattedFileCount formats numbers correctly', () {
      final model =
          IndexModel(name: '', sourcePath: '', lynPath: '', indexPath: '')
            ..name = 'test'
            ..sourcePath = '/test/path'
            ..fileCount = 1500
            ..createdAt = DateTime.now()
            ..lastIndexedAt = DateTime.now();

      expect(model.formattedFileCount, '1.5K');
    });

    test('formattedLastModified shows relative time', () {
      final now = DateTime.now();
      final model =
          IndexModel(name: '', sourcePath: '', lynPath: '', indexPath: '')
            ..name = 'test'
            ..sourcePath = '/test/path'
            ..fileCount = 100
            ..createdAt = now
            ..lastIndexedAt = now.subtract(const Duration(hours: 2));

      expect(model.formattedLastModified, '2h ago');
    });

    test('isServerRunning returns true when HTTP server is active', () {
      final model =
          IndexModel(name: '', sourcePath: '', lynPath: '', indexPath: '')
            ..name = 'test'
            ..sourcePath = '/test/path'
            ..fileCount = 100
            ..createdAt = DateTime.now()
            ..lastIndexedAt = DateTime.now();
      expect(model.isServerRunning, true);
    });
  });
}
