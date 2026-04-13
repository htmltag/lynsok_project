import 'dart:io' as io;

import 'package:lynsok_core/lynsok_runner.dart';
import 'package:test/test.dart';

void main() {
  group('LynSokSearcher rawSearch', () {
    test('returns plain snippet with explicit match metadata', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final input = io.File('${tempDir.path}/doc.txt');
        await input.writeAsString(
          'This is a test sentence for metadata checks.',
        );

        final archive = io.File('${tempDir.path}/archive.lyn');
        final runner = LynSokRunner(
          isolates: 1,
          patterns: const {},
          caseInsensitive: true,
          jsonMode: false,
          compactOutput: archive.path,
        );
        await runner.run(tempDir.path);

        final searcher = LynSokSearcher(
          archiveFile: archive,
          indexPath: '${archive.path}.idx.missing',
        );

        final results = await searcher.rawSearch('test', maxResults: 5);
        expect(results, isNotEmpty);

        final first = results.first;
        expect(first.snippet.toLowerCase(), contains('test'));
        expect(first.snippet, isNot(contains('\x1b[33m')));
        expect(first.snippet, isNot(contains('\x1b[0m')));
        expect(first.matchedTerms, contains('test'));
        expect(first.matchRanges, isNotEmpty);

        final testRanges = first.matchRanges
            .where((range) => range.term == 'test')
            .toList(growable: false);
        expect(testRanges, isNotEmpty);
        final firstRange = testRanges.first;
        expect(firstRange.end, greaterThan(firstRange.start));
        expect(
          first.snippet
              .substring(firstRange.start, firstRange.end)
              .toLowerCase(),
          equals('test'),
        );
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });

    test('uses UTF-8 byte offset for raw-search matchOffset', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final input = io.File('${tempDir.path}/unicode.txt');
        const content = 'ååå test appears after multibyte chars';
        await input.writeAsString(content);

        final archive = io.File('${tempDir.path}/archive.lyn');
        final runner = LynSokRunner(
          isolates: 1,
          patterns: const {},
          caseInsensitive: true,
          jsonMode: false,
          compactOutput: archive.path,
        );
        await runner.run(tempDir.path);

        final searcher = LynSokSearcher(
          archiveFile: archive,
          indexPath: '${archive.path}.idx.missing',
        );

        final results = await searcher.rawSearch('test', maxResults: 5);
        expect(results, isNotEmpty);

        final first = results.first;
        // "ååå " is 4 characters and 7 bytes in UTF-8.
        expect(first.matchOffset, equals(7));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });
  });
}
