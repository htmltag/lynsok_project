import 'dart:isolate';
import 'dart:typed_data';
import 'dart:io'; // needed for ZLibDecoder

// bring in the shared FileType enum so we can react appropriately
import '../core/file_types.dart';
import 'stream_extractor.dart';

void logProcessorEntryPoint(SendPort supervisorPort) {
  final rp = ReceivePort();
  supervisorPort.send({'type': 'workerReady', 'port': rp.sendPort});

  rp.listen((message) {
    if (message is! Map || message['type'] != 'work') return;

    try {
      final ttd = message['data'] as TransferableTypedData;
      final bool isFirst = message['isFirst'] as bool;
      final int baseSize = message['baseSize'] as int;
      final bool caseInsensitive = message['caseInsensitive'] ?? true;
      final bool isJsonMode = message['isJsonMode'] ?? false;
      final Map<String, Uint8List> patterns = Map.from(message['patterns']);
      final String mode = message['mode'] as String? ?? 'search';

      final bytes = ttd.materialize().asUint8List();
      final int len = bytes.length;

      // determine what kind of data we're working on; gracefully handle missing info
      final int ftIndex = message['fileType'] as int? ?? FileType.unknown.index;
      final FileType fileType = FileType.values[ftIndex];

      // --- 1. ROBUST BOUNDARY SNAPPING ---

      // START: If not the first chunk, skip the partial line at the beginning
      int start = 0;
      if (!isFirst) {
        final firstNewline = bytes.indexOf(10);
        if (firstNewline == -1) {
          // No newline in this entire 9MB block? Rare, but we must exit safely.
          supervisorPort.send({
            'type': 'result',
            'id': message['id'],
            'counts': {},
          });
          return;
        }
        start = firstNewline + 1;
      }

      // END: Find the first newline AT or AFTER the baseSize mark.
      // This ensures we finish the line that was "cut" at the 8MB mark.
      int end = bytes.indexOf(10, baseSize);

      // FIX: If no newline is found in the overlap (EOF) or it's out of range,
      // clamp it to the actual length of the byte array.
      if (end == -1 || end >= len) {
        end = len;
      }

      if (mode == 'compact') {
        // simply extract text and send it back
        final extracted = extractFromChunk(bytes, start, end, fileType);
        supervisorPort.send({
          'type': 'result',
          'id': message['id'],
          'counts': <String, int>{},
          'executionMs': 0.0,
          'extracted': TransferableTypedData.fromList([extracted]),
        });
      } else {
        // --- 2. MULTI-PATTERN SEARCH ---
        Map<String, int> results;
        if (fileType == FileType.pdf) {
          results = _huntPdfCompressedStreams(bytes, start, end);
        } else if (fileType == FileType.docx) {
          results = _processDocxChunk(bytes, patterns, caseInsensitive);
        } else if (isJsonMode) {
          results = _performLazyJsonLevelExtraction(bytes, start, end);
        } else {
          results = _performMultiByteSearch(
            bytes,
            patterns,
            start,
            end,
            caseInsensitive,
          );
        }

        supervisorPort.send({
          'type': 'result',
          'id': message['id'],
          'counts': results,
        });
      }
    } catch (e, st) {
      // Always send a response so the Supervisor doesn't hang
      supervisorPort.send({
        'type': 'result',
        'id': message['id'],
        'counts': {},
        'error': e.toString(),
        'stack': st.toString(),
      });
    }
  });
}

/// A specialized function to extract "level" values from JSON logs without full parsing.
Map<String, int> _performLazyJsonLevelExtraction(
  Uint8List source,
  int start,
  int end,
) {
  final counts = <String, int>{};

  // ASCII for '"level":' -> [34, 108, 101, 118, 101, 108, 34, 58]
  final Uint8List levelKey = Uint8List.fromList([
    34,
    108,
    101,
    118,
    101,
    108,
    34,
    58,
  ]);
  final int keyLen = levelKey.length;

  for (int i = start; i < end - keyLen; i++) {
    // 1. High-speed check for the first '"' of "level":
    if (source[i] != 34) continue;

    // 2. Check if the next bytes match "level":
    bool match = true;
    for (int j = 1; j < keyLen; j++) {
      if (source[i + j] != levelKey[j]) {
        match = false;
        break;
      }
    }

    if (match) {
      // 3. We found the key! Now find the value inside the next quotes.
      // Move 'i' to the end of '"level":'
      int cursor = i + keyLen;

      // Skip whitespace/colon if any (though structured JSON is usually tight)
      while (cursor < end && (source[cursor] == 32 || source[cursor] == 58)) {
        cursor++;
      }

      // Find the opening quote of the value
      while (cursor < end && source[cursor] != 34) {
        cursor++;
      }

      if (cursor < end && source[cursor] == 34) {
        cursor++; // Skip the opening quote
        int valStart = cursor;

        // Find the closing quote
        while (cursor < end && source[cursor] != 34) {
          cursor++;
        }

        if (cursor < end) {
          // 4. Extract the level (e.g., "ERROR")
          // We convert to String here ONLY for the small label, not the whole 8MB
          final String level = String.fromCharCodes(source, valStart, cursor);
          counts[level] = (counts[level] ?? 0) + 1;

          i = cursor; // Jump ahead
        }
      }
    }
  }
  return counts;
}

/// Single-pass Multi-pattern Search
Map<String, int> _performMultiByteSearch(
  Uint8List source,
  Map<String, Uint8List> patterns,
  int start,
  int end,
  bool caseInsensitive,
) {
  final counts = <String, int>{for (var label in patterns.keys) label: 0};
  final patternEntries = patterns.entries.toList();

  // 1. Pre-calculate the Lookup Table (Fast Gatekeeper)
  final Uint8List firstByteLookup = Uint8List(256);
  for (var p in patterns.values) {
    if (p.isEmpty) continue;
    firstByteLookup[p[0]] = 1;
    if (caseInsensitive) {
      firstByteLookup[_getAltCase(p[0])] = 1;
    }
  }

  // 2. The Main Scan
  for (int i = start; i < end; i++) {
    // 95% of bytes fail here instantly (High Speed)
    if (firstByteLookup[source[i]] == 0) continue;

    final int currentByte = source[i];

    for (var entry in patternEntries) {
      final p = entry.value;

      // Safety: Don't look past the snapped 'end' boundary
      if (i + p.length > end) continue;

      if (_compare(currentByte, p[0], caseInsensitive)) {
        bool match = true;
        for (int j = 1; j < p.length; j++) {
          if (!_compare(source[i + j], p[j], caseInsensitive)) {
            match = false;
            break;
          }
        }

        if (match) {
          counts[entry.key] = (counts[entry.key] ?? 0) + 1;
          // Note: Not skipping 'i' here allows overlapping pattern detection
        }
      }
    }
  }
  return counts;
}

/// Bit-wise comparison for case-insensitivity (ASCII only)
bool _compare(int a, int b, bool caseInsensitive) {
  if (a == b) return true;
  if (!caseInsensitive) return false;
  // Check if they are the same letter with a case flip (32 bit)
  return (a ^ b) == 32 && ((a >= 65 && a <= 90) || (a >= 97 && a <= 122));
}

/// Returns the opposite case for A-Z / a-z
int _getAltCase(int byte) {
  if (byte >= 65 && byte <= 90) return byte + 32;
  if (byte >= 97 && byte <= 122) return byte - 32;
  return byte;
}

/// Simple scan that counts occurrences of "/Filter" as a proxy for
/// compressed streams inside a PDF page.  The pattern is cheap and the
/// resulting map uses the fixed label "compressedStreams" so callers can
/// aggregate counts across chunks.
Map<String, int> _huntPdfCompressedStreams(
  Uint8List source,
  int start,
  int end,
) {
  int count = 0;
  // ASCII for "/Filter" (47,70,105,108,116,101,114)
  final Uint8List pattern = Uint8List.fromList([
    47,
    70,
    105,
    108,
    116,
    101,
    114,
  ]);
  for (int i = start; i <= end - pattern.length; i++) {
    bool match = true;
    for (int j = 0; j < pattern.length; j++) {
      if (source[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) count++;
  }
  return {'compressedStreams': count};
}

/// Scan a raw chunk of bytes from a docx/zip file looking for the
/// "word/document.xml" entry.  When found, attempt to decompress that
/// file (might fail on a partial chunk) and run the standard
/// byte-search over the decompressed XML contents.
Map<String, int> _processDocxChunk(
  Uint8List bytes,
  Map<String, Uint8List> patterns,
  bool caseInsensitive,
) {
  final counts = <String, int>{for (var k in patterns.keys) k: 0};
  int pos = 0;

  // 1. Search for Zip Local File Header: [0x50, 0x4B, 0x03, 0x04]
  while (pos < bytes.length - 30) {
    if (bytes[pos] == 0x50 &&
        bytes[pos + 1] == 0x4B &&
        bytes[pos + 2] == 0x03 &&
        bytes[pos + 3] == 0x04) {
      // 2. Read the filename length (offset 26, 2 bytes)
      int nameLen = bytes[pos + 26] | (bytes[pos + 27] << 8);
      int extraLen = bytes[pos + 28] | (bytes[pos + 29] << 8);

      // 3. Check if this is the "word/document.xml" file
      String internalName = String.fromCharCodes(
        bytes,
        pos + 30,
        pos + 30 + nameLen,
      );

      if (internalName == 'word/document.xml') {
        // 4. Find the compressed data start
        int dataStart = pos + 30 + nameLen + extraLen;

        // Read compressed size from header (offset 18)
        int compressedSize =
            bytes[pos + 18] |
            (bytes[pos + 19] << 8) |
            (bytes[pos + 20] << 16) |
            (bytes[pos + 21] << 24);

        if (dataStart + compressedSize <= bytes.length) {
          try {
            final compressedData = bytes.sublist(
              dataStart,
              dataStart + compressedSize,
            );

            // 5. "Raw" Decompress (Inflate)
            // Note: ZIP uses 'raw' ZLib (no headers), so we use ZLibDecoder(raw: true)
            final decompressed = Uint8List.fromList(
              ZLibDecoder(raw: true).convert(compressedData),
            );

            // 6. Search the XML text (we ignore tags and just grep the content)
            final subResults = _performMultiByteSearch(
              decompressed,
              patterns,
              0,
              decompressed.length,
              caseInsensitive,
            );
            subResults.forEach((k, v) => counts[k] = counts[k]! + v);
          } catch (_) {
            // decompression can fail for partial chunks; ignore and continue
          }
        }
      }
      pos += 30 + nameLen + extraLen; // Jump to next possible header
    } else {
      pos++;
    }
  }

  return counts;
}
