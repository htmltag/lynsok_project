// Helpers for the LynSok Archive (LYN) record format.
import 'dart:io';

///
/// Structure (big-endian integers):
/// [Magic Number (4 bytes: "BONS")]
/// [Version (2 bytes)]
/// Then for each record:
///   STX (1 byte = 0x02)
///   PathLength (4 bytes)
///   Path (utf8)
///   BodyLength (8 bytes; placeholder initially)
///   Body (text bytes)
///   ETX (1 byte = 0x03)

import 'dart:convert';
import 'dart:typed_data';

const List<int> lynMagic = [0x42, 0x4F, 0x4E, 0x53]; // "BONS"
const List<int> lynVersion = [0x00, 0x01];

const int stx = 0x02;
const int etx = 0x03;

Uint8List int32ToBytes(int value) {
  final bytes = ByteData(4);
  bytes.setUint32(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

Uint8List int64ToBytes(int value) {
  final bytes = ByteData(8);
  bytes.setUint64(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

/// Write a record header to [raf], returning the offset of the body-length field
/// so it can be patched later.
Future<int> writeRecordHeader(RandomAccessFile raf, String path) async {
  final pathBytes = utf8.encode(path);
  await raf.writeByte(stx);
  await raf.writeFrom(int32ToBytes(pathBytes.length));
  await raf.writeFrom(pathBytes);
  // remember offset for body length
  final lengthOffset = await raf.position();
  await raf.writeFrom(int64ToBytes(0)); // placeholder
  return lengthOffset;
}

/// Patch the body length at [offset] with the given value.
Future<void> patchBodyLength(
  RandomAccessFile raf,
  int offset,
  int length,
) async {
  await raf.setPosition(offset);
  await raf.writeFrom(int64ToBytes(length));
}
