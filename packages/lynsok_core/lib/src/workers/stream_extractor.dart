import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import '../core/file_types.dart';

/// Entrypoint for extraction; returns only clean text.
Uint8List extractFromChunk(
  Uint8List bytes,
  int start,
  int end,
  FileType fileType,
) {
  Uint8List raw;
  if (fileType == FileType.pdf) {
    raw = _extractPdfStreams(bytes, start, end);
  } else if (fileType == FileType.docx) {
    raw = _extractDocxText(bytes, start, end);
  } else {
    raw = bytes.sublist(start, end);
  }
  return _ensureUtf8(raw);
}

Uint8List _extractPdfStreams(Uint8List source, int start, int end) {
  final List<int> output = [];
  int pos = start;

  // Tokens for PDF stream boundaries
  const List<int> streamToken = [115, 116, 114, 101, 97, 109]; // "stream"
  const List<int> endToken = [
    101,
    110,
    100,
    115,
    116,
    114,
    101,
    97,
    109,
  ]; // "endstream"

  while (pos < end) {
    final int idx = _indexOf(source, streamToken, pos, end);
    if (idx == -1) break;

    int dataStart = idx + streamToken.length;
    // Handle CRLF or LF after 'stream'
    if (dataStart < end &&
        (source[dataStart] == 0x0A || source[dataStart] == 0x0D)) {
      dataStart++;
      if (dataStart < end && source[dataStart] == 0x0A) dataStart++;
    }

    final int idx2 = _indexOf(source, endToken, dataStart, end);
    if (idx2 == -1) break;

    final Uint8List candidate = source.sublist(dataStart, idx2);

    try {
      // Decompress
      Uint8List? decompressed;
      try {
        decompressed = Uint8List.fromList(
          ZLibDecoder(raw: false).convert(candidate),
        );
      } catch (_) {
        try {
          decompressed = Uint8List.fromList(
            ZLibDecoder(raw: true).convert(candidate),
          );
        } catch (_) {
          decompressed = null;
        }
      }

      // If decompression succeeded, parse the content
      if (decompressed != null && decompressed.isNotEmpty) {
        // Limit decoding to 10MB to prevent memory-related deadlocks on massive streams
        if (decompressed.length < 10 * 1024 * 1024) {
          final cleanText = _parsePdfContent(decompressed);
          if (cleanText.isNotEmpty) {
            output.addAll(utf8.encode('$cleanText '));
          }
        }
      }
    } catch (_) {}

    pos = idx2 + endToken.length;
  }
  return Uint8List.fromList(output);
}

/// Parses PDF content streams for text inside () or <>.
String _parsePdfContent(Uint8List decompressed) {
  final content = utf8.decode(decompressed, allowMalformed: true);
  final buffer = StringBuffer();

  // 1. Improved Parentheses Extraction
  final RegExp parenRegex = RegExp(r'\((.*?)\)');
  for (final match in parenRegex.allMatches(content)) {
    String text = match.group(1) ?? '';
    if (text.length < 2 && text.trim().isEmpty) continue;

    // Fix Octal: \323 -> Ó
    text = text.replaceAllMapped(RegExp(r'\\(\d{1,3})'), (m) {
      try { return String.fromCharCode(int.parse(m.group(1)!, radix: 8)); } catch (_) { return ''; }
    });

    text = text.replaceAll(r'\(', '(').replaceAll(r'\)', ')').replaceAll(r'\\', r'\');
    
    // Only add if it actually looks like text (prevents binary junk)
    if (RegExp(r'[a-zA-Z0-9áéíóúÁÉÍÓÚñÑ]').hasMatch(text)) {
      buffer.write('$text ');
    }
  }

  // 2. Improved Hex Extraction (Handles UTF-16BE hex found in technical papers)
  final RegExp hexRegex = RegExp(r'<([0-9a-fA-F]{2,})>');
  for (final match in hexRegex.allMatches(content)) {
    String hex = match.group(1) ?? '';
    try {
      final List<int> hexBytes = [];
      for (int i = 0; i < hex.length; i += 2) {
        hexBytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      
      // Try UTF-16BE (Common in modern/technical PDFs)
      if (hexBytes.length >= 2 && hexBytes[0] == 0x00) {
          buffer.write('${String.fromCharCodes(hexBytes)} ');
      } else {
         buffer.write('${utf8.decode(hexBytes, allowMalformed: true)} ');
      }
    } catch (_) {}
  }

  return buffer.toString().trim();
}

Uint8List _extractDocxText(Uint8List bytes, int start, int end) {
  final List<int> output = [];
  int pos = start;
  while (pos < end - 30) {
    if (bytes[pos] == 0x50 &&
        bytes[pos + 1] == 0x4B &&
        bytes[pos + 2] == 0x03 &&
        bytes[pos + 3] == 0x04) {
      int nameLen = bytes[pos + 26] | (bytes[pos + 27] << 8);
      int extraLen = bytes[pos + 28] | (bytes[pos + 29] << 8);
      String internalName = String.fromCharCodes(
        bytes,
        pos + 30,
        pos + 30 + nameLen,
      );

      if (internalName == 'word/document.xml') {
        int dataStart = pos + 30 + nameLen + extraLen;
        int compSize =
            bytes[pos + 18] |
            (bytes[pos + 19] << 8) |
            (bytes[pos + 20] << 16) |
            (bytes[pos + 21] << 24);
        if (dataStart + compSize <= bytes.length) {
          try {
            final decompressed = ZLibDecoder(
              raw: true,
            ).convert(bytes.sublist(dataStart, dataStart + compSize));
            final text = utf8.decode(decompressed, allowMalformed: true);
            output.addAll(utf8.encode(_cleanXml(text)));
          } catch (_) {}
        }
      }
      pos += 30 + nameLen + extraLen;
    } else {
      pos++;
    }
  }
  return Uint8List.fromList(output);
}

String _cleanXml(String input) {
  var cleaned = input.replaceAll(
    RegExp(r'<w:binData[^>]*>.*?</w:binData>', dotAll: true),
    '',
  );
  cleaned = cleaned.replaceAll(RegExp(r'<[^>]*>'), ' ');
  return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Uint8List _ensureUtf8(Uint8List input) {
  try {
    return Uint8List.fromList(utf8.encode(utf8.decode(input)));
  } catch (_) {
    return Uint8List.fromList(
      utf8.encode(latin1.decode(input, allowInvalid: true)),
    );
  }
}

int _indexOf(Uint8List haystack, List<int> needle, int start, int end) {
  if (needle.isEmpty) return -1;
  for (int i = start; i <= end - needle.length; i++) {
    bool match = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
