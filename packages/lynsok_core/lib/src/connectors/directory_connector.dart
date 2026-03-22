import 'dart:io';

import '../connectors/file_connector.dart';

/// A connector that reads all files in a directory (recursively) and yields their contents as transferable typed data chunks.
/// This is designed to be used in an isolate, allowing for efficient file reading without blocking the main thread.
/// The chunk size can be configured, and an overlap is included to ensure that lines that span across chunks are not split in the middle.
/// Example usage:
/// ```dart
/// final connector = DirectoryConnector('path/to/directory');
/// await for (final chunk in connector.streamChunks()) {
/// // Process the chunk (e.g., send it to another isolate)
/// }
/// ```
class DirectoryConnector {
  final String path;
  final int chunkSize;

  DirectoryConnector(this.path, {this.chunkSize = 8388608});

  Stream<Map<String, dynamic>> streamChunks() async* {
    final dir = Directory(path);
    final files = dir.list(recursive: true).where((item) => item is File);

    await for (final file in files) {
      final connector = FileConnector(file.path, chunkSize: chunkSize);
      await for (final chunk in connector.streamChunks()) {
        yield chunk;
      }
    }
  }
}
