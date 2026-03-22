import 'dart:io';

enum PathType { file, directory, notFound }

/// Utility to determine if a given path is a file, directory, or does not exist.
/// This is used in the CLI to decide how to process the input path (e.g., whether to scan a directory or read a single file).
/// This is a simple wrapper around Dart's `File` and `Directory` existence checks, providing a clear enum-based result that can be used in control flow. It helps centralize the logic for path type detection and keeps the main runner code cleaner.
class DirectoryScanner {
  static PathType getPathType(String path) {
    if (Directory(path).existsSync()) {
      return PathType.directory;
    } else if (File(path).existsSync()) {
      return PathType.file;
    } else {
      return PathType.notFound;
    }
  }
}
