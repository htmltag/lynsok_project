import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'lyn_format.dart';

/// Parses the given `.lyn` file and returns a list of records.
///
/// Each record is a map containing:
///   - `path`: String absolute path of the source file
///   - `body`: Uint8List of the extracted text bytes
///
/// Throws [FormatException] if the file does not conform to the LynSok format.
Future<List<Map<String, dynamic>>> parseLyn(File file) async {
  final bytes = await file.readAsBytes();
  final reader = ByteData.sublistView(bytes);
  int offset = 0;

  // verify magic + version
  for (var b in lynMagic) {
    if (offset >= bytes.length || reader.getUint8(offset) != b) {
      throw FormatException('Invalid Lyn magic number at offset $offset');
    }
    offset++;
  }
  // skip version
  offset += lynVersion.length;

  final records = <Map<String, dynamic>>[];
  while (offset < bytes.length) {
    try {
      final byte = reader.getUint8(offset);
      if (byte != stx) {
        throw FormatException('Expected STX at offset $offset, found $byte');
      }
      offset++;
      final pathLen = reader.getUint32(offset, Endian.big);
      offset += 4;
      final path = utf8.decode(bytes.sublist(offset, offset + pathLen));
      offset += pathLen;
      final bodyLen = reader.getUint64(offset, Endian.big);
      offset += 8;
      if (offset + bodyLen > bytes.length) {
        throw FormatException('Body length $bodyLen extends past EOF');
      }
      final body = bytes.sublist(offset, offset + bodyLen);
      offset += bodyLen;
      if (offset >= bytes.length || reader.getUint8(offset) != etx) {
        throw FormatException('Expected ETX after body for $path');
      }
      offset++;
      records.add({'path': path, 'body': body});
    } catch (e) {
      stderr.writeln('warning: encountered bad record at offset $offset: $e');
      // try to recover: look for the next STX marker in the stream and
      // resume parsing there.  if none is found we bail out.
      final next = bytes.indexOf(stx, offset + 1);
      if (next == -1) break;
      offset = next;
      continue;
    }
  }

  return records;
}
