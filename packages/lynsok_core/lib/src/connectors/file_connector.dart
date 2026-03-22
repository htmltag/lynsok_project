import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';

/// A connector that reads a file in chunks and yields them as transferable typed data.
/// This is designed to be used in an isolate, allowing for efficient file reading without blocking the main thread.
/// The chunk size can be configured, and an overlap is included to ensure that lines that span across chunks are not split in the middle.
/// Example usage:
/// ```dart
/// final connector = FileConnector('path/to/large/file.txt');
/// await for (final chunk in connector.streamChunks()) {
/// // Process the chunk (e.g., send it to another isolate)
/// }
/// ```
class FileConnector {
  final String path;
  final int chunkSize;
  final int overlapSize = 1024 * 1024; // 1MB Safety Buffer for long lines

  FileConnector(this.path, {this.chunkSize = 8388608}); // Default 8MB

  Stream<Map<String, dynamic>> streamChunks() async* {
    final file = File(path);
    final raf = await file.open(mode: FileMode.read);

    try {
      final int fileLength = await raf.length();
      int position = 0;
      int chunkId = 0;

      while (position < fileLength) {
        await raf.setPosition(position);

        // Read chunkSize + overlapSize (e.g. 9MB total)
        int toRead = chunkSize + overlapSize;
        if (position + toRead > fileLength) {
          toRead = fileLength - position;
        }

        final Uint8List buffer = await raf.read(toRead);

        final bool isLastChunk = position + toRead >= fileLength;
        yield {
          'id': chunkId++,
          'data': TransferableTypedData.fromList([buffer]),
          'isFirst': position == 0,
          'baseSize': chunkSize, // The "Target" size
          'path': path,
          'isLast': isLastChunk,
        };

        // We only move the file pointer by chunkSize
        position += chunkSize;
      }
    } finally {
      await raf.close();
    }
  }
}
