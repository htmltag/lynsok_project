import 'dart:io' as io;
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:lynsok_core/src/workers/stream_extractor.dart';
import 'package:lynsok_core/src/runner.dart';
import 'package:lynsok_core/src/core/file_types.dart';
import 'package:lynsok_core/src/utils/lyn_reader.dart';
import 'package:lynsok_core/src/connectors/file_connector.dart';
import 'package:path/path.dart' as p; // for normalization

/// Helper for building a minimal PDF-like byte sequence containing a single
/// "stream" block with zlib-compressed text.
Uint8List makeFakePdf(String text) {
  // use dart:io encoder with raw deflate mode
  final encoder = io.ZLibEncoder(raw: true);
  final compressed = encoder.convert(utf8.encode(text));
  // include a bogus PDF header so FileSniffer recognizes the file
  final prefix = utf8.encode('%PDF-1.0\n');
  final header = utf8.encode('abc stream\n');
  final footer = utf8.encode('\nendstream xyz');
  final bytes = <int>[];
  bytes.addAll(prefix);
  bytes.addAll(header);
  bytes.addAll(compressed);
  bytes.addAll(footer);
  return Uint8List.fromList(bytes);
}

/// Helper to build an in-memory .docx archive containing `word/document.xml`
/// with [text] inside a simple tag.
Uint8List makeFakeDocx(String text) {
  final arch = Archive();
  final xml =
      '<w:document><w:body><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:body></w:document>';
  arch.addFile(ArchiveFile('word/document.xml', xml.length, utf8.encode(xml)));
  final data = ZipEncoder().encode(arch);
  return Uint8List.fromList(data);
}

void main() {
  group('stream extractor helpers', () {
    test('pdf stream extraction returns decompressed text', () {
      final pdf = makeFakePdf('hello world');
      final extracted = extractFromChunk(pdf, 0, pdf.length, FileType.pdf);
      expect(utf8.decode(extracted), contains('hello world'));
    });

    test('normalizes latin1 bytes to utf8', () {
      // construct a byte sequence containing the latin1 code for 'å' (0xE5)
      final latin1 = Uint8List.fromList([
        0x41,
        0x20,
        0xE5,
      ]); // "A å" in ISO-8859-1
      final out = extractFromChunk(latin1, 0, latin1.length, FileType.unknown);
      expect(utf8.decode(out), equals('A å'));
    });

    test('docx extraction strips xml tags and returns text', () {
      final docx = makeFakeDocx('foobar');
      final extracted = extractFromChunk(docx, 0, docx.length, FileType.docx);
      final txt = utf8.decode(extracted);
      expect(txt, contains('foobar'));
      expect(txt, isNot(contains('<w:')));
    });

    test('docx extraction removes tags even when image data is present', () {
      // build a manual document.xml that contains a fake <image> tag before the
      // text.  the regex should drop the tag entirely and leave only "hello".
      final xml =
          '<w:document><w:body>'
          '<w:p><w:binData>BASE64DATA</w:binData><w:t>hello</w:t></w:p>'
          '</w:body></w:document>';
      final arch = Archive();
      arch.addFile(
        ArchiveFile('word/document.xml', xml.length, utf8.encode(xml)),
      );
      final data = ZipEncoder().encode(arch);
      final extracted = extractFromChunk(
        Uint8List.fromList(data),
        0,
        data.length,
        FileType.docx,
      );
      final txt = utf8.decode(extracted);
      expect(txt, equals('hello'));
    });

    test('long base64 segments are stripped even without binData tags', () {
      final xml =
          '<w:document><w:body><w:p>ABC${'A' * 200}DEF<w:t>word</w:t></w:p></w:body></w:document>'; // the long run of A's simulates a base64-encoded image that should be stripped
      final arch = Archive();
      arch.addFile(
        ArchiveFile('word/document.xml', xml.length, utf8.encode(xml)),
      );
      final data = ZipEncoder().encode(arch);
      final extracted = extractFromChunk(
        Uint8List.fromList(data),
        0,
        data.length,
        FileType.docx,
      );
      final txt = utf8.decode(extracted);
      // the long run of A's should be removed, leaving just "ABC DEF word".
      expect(txt, contains('word'));
      expect(txt, isNot(contains('A' * 50)));
    });
  });

  group('connectors', () {
    test('FileConnector yields path and isLast flags', () async {
      final tmp = io.File('tmp_test.txt');
      await tmp.writeAsString('line1\nline2');
      final connector = FileConnector(tmp.path, chunkSize: 5);
      final chunks = <Map<String, dynamic>>[];
      await for (final c in connector.streamChunks()) {
        chunks.add(c);
      }
      expect(chunks, isNotEmpty);
      expect(chunks.first['path'], equals(tmp.path));
      expect(chunks.last['isLast'], isTrue);
      await tmp.delete();
    });
  });

  group('end-to-end compact mode', () {
    test(
      'creates a valid .lyn with all records',
      () async {
        final tempDir = io.Directory.systemTemp.createTempSync('lynsok_test');
        try {
          // create files
          final f1 = io.File('${tempDir.path}/a.txt');
          await f1.writeAsString('plaintext');
          final f2 = io.File('${tempDir.path}/b.pdf');
          await f2.writeAsBytes(makeFakePdf('pdftext'));
          final f3 = io.File('${tempDir.path}/c.docx');
          await f3.writeAsBytes(makeFakeDocx('doctext'));
          // add a PDF whose raw text bytes are formatted in Latin-1 rather than
          // UTF-8 so that we can ensure normalization happens end-to-end
          final f4 = io.File('${tempDir.path}/d.pdf');
          // compress using latin1 encoding explicitly
          final latin1Encoder = io.ZLibEncoder(raw: true);
          final latin1Compressed = latin1Encoder.convert(latin1.encode('å'));
          final prefix = utf8.encode('%PDF-1.0\n');
          final header = utf8.encode('abc stream\n');
          final footer = utf8.encode('\nendstream xyz');
          final pdfbytes = <int>[
            ...prefix,
            ...header,
            ...latin1Compressed,
            ...footer,
          ];
          await f4.writeAsBytes(Uint8List.fromList(pdfbytes));

          final archive = io.File('${tempDir.path}/out.lyn');
          final runner = LynSokRunner(
            isolates: 1,
            patterns: {},
            caseInsensitive: true,
            jsonMode: false,
            compactOutput: archive.path,
          );
          await runner.run(tempDir.path);

          final recs = await parseLyn(archive);
          // Normalize separators so tests are stable across platforms
          final paths = recs
              .map((r) => p.normalize(r['path'] as String))
              .toList();
          final expectedPaths = [
            f1.path,
            f2.path,
            f3.path,
            f4.path,
          ].map(p.normalize).toList();
          expect(paths, containsAll(expectedPaths));
          expect(
            utf8.decode(
              recs.firstWhere(
                (r) => p.normalize(r['path'] as String) == p.normalize(f1.path),
              )['body'],
            ),
            contains('plaintext'),
          );
          expect(
            utf8.decode(
              recs.firstWhere(
                (r) => p.normalize(r['path'] as String) == p.normalize(f2.path),
              )['body'],
            ),
            contains('pdftext'),
          );
          expect(
            utf8.decode(
              recs.firstWhere(
                (r) => p.normalize(r['path'] as String) == p.normalize(f3.path),
              )['body'],
            ),
            contains('doctext'),
          );
          expect(
            utf8.decode(
              recs.firstWhere(
                (r) => p.normalize(r['path'] as String) == p.normalize(f4.path),
              )['body'],
            ),
            contains('å'),
          );
        } finally {
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {
            // on Windows the file may still be locked briefly; ignore
          }
        }
      },
      timeout: Timeout(Duration(seconds: 10)),
    );

    test('can convert archive to newline JSON records', () async {
      final tempDir2 = io.Directory.systemTemp.createTempSync('lynsok_test2');
      try {
        // create two simple files
        final f1 = io.File('${tempDir2.path}/x.txt');
        await f1.writeAsString('foo');
        final f2 = io.File('${tempDir2.path}/y.txt');
        await f2.writeAsString('bar');
        final archive = io.File('${tempDir2.path}/z.lyn');

        final runner = LynSokRunner(
          isolates: 1,
          patterns: {},
          caseInsensitive: true,
          jsonMode: false,
          compactOutput: archive.path,
        );
        await runner.run(tempDir2.path);

        final recs = await parseLyn(archive);
        final jsonPath = '${tempDir2.path}/out.json';
        final outSink = io.File(jsonPath).openWrite();
        for (var r in recs) {
          outSink.writeln(
            jsonEncode({
              'path': r['path'],
              'text': utf8.decode(r['body'] as Uint8List),
            }),
          );
        }
        await outSink.flush();
        await outSink.close();

        final lines = await io.File(jsonPath).readAsLines();
        expect(lines.length, equals(2));
        final objs = lines.map((l) => jsonDecode(l) as Map).toList();
        expect(objs.map((o) => o['text']), containsAll(['foo', 'bar']));
      } finally {
        try {
          await tempDir2.delete(recursive: true);
        } catch (_) {}
      }
    });
  });
}
