import 'dart:typed_data';
import '../core/file_types.dart';

/// Utility to detect file types based on magic numbers and content heuristics.
/// This is used to determine how to process files during indexing and searching.
/// Currently supports PDF, DOCX, JSON, Markdown, and defaults to plain text.
/// This is a best-effort approach and may not be 100% accurate for all files, but it helps optimize processing by quickly identifying common formats.
/// For example, it allows us to apply PDF stream extraction logic only to files that are likely PDFs, rather than trying to parse every file as a PDF.
/// The detection is based on the first few bytes of the file, which is a common technique for file type identification. It checks for specific "magic numbers" that are characteristic of certain formats (e.g., "%PDF" for PDFs, "PK.." for ZIP-based formats like DOCX). For JSON and Markdown, it uses simple heuristics based on typical starting characters. If none of the specific types are detected, it falls back to treating the file as plain text.
class FileSniffer {
  // Magic Numbers
  static const List<int> pdfMagic = [0x25, 0x50, 0x44, 0x46]; // %PDF
  static const List<int> zipMagic = [0x50, 0x4B, 0x03, 0x04]; // PK.. (Docx/Zip)

  static FileType detect(Uint8List chunk) {
    if (chunk.length < 4) return FileType.unknown;

    // 1. Check PDF
    if (_matches(chunk, pdfMagic)) return FileType.pdf;

    // 2. Check DOCX (Starts as a ZIP)
    if (_matches(chunk, zipMagic)) return FileType.docx;

    // 3. Check JSON
    // JSON usually starts with '{' (123) or '[' (91), possibly preceded by whitespace
    int firstByte = _firstNonWhitespace(chunk);
    if (firstByte == 123 || firstByte == 91) return FileType.json;

    // 4. Check Markdown
    // Harder to "guarantee", but we look for common MD starts like '# ' (35, 32)
    if (chunk.length >= 2 && chunk[0] == 35 && chunk[1] == 32) {
      return FileType.markdown;
    }

    // 5. Default to Text
    return FileType.text;
  }

  static bool _matches(Uint8List chunk, List<int> magic) {
    for (int i = 0; i < magic.length; i++) {
      if (chunk[i] != magic[i]) return false;
    }
    return true;
  }

  static int _firstNonWhitespace(Uint8List chunk) {
    for (int b in chunk) {
      if (b != 32 && b != 10 && b != 13 && b != 9) return b;
    }
    return -1;
  }
}
