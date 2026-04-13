import 'dart:io' as io;

import 'package:lynsok_core/lynsok_runner.dart';
import 'package:test/test.dart';

Future<LynSokSearcher> _buildSearcherWithIndex(
  io.Directory tempDir,
  Map<String, String> files,
) async {
  for (final entry in files.entries) {
    final file = io.File('${tempDir.path}/${entry.key}');
    await file.writeAsString(entry.value);
  }

  final archive = io.File('${tempDir.path}/archive.lyn');
  final runner = LynSokRunner(
    isolates: 1,
    patterns: const {},
    caseInsensitive: true,
    jsonMode: false,
    compactOutput: archive.path,
    buildIndex: true,
  );
  await runner.run(tempDir.path);

  final searcher = LynSokSearcher(
    archiveFile: archive,
    indexPath: '${archive.path}.idx',
  );
  await searcher.loadIndex();
  return searcher;
}

Future<LynSokSearcher> _buildSearcherForContent(
  io.Directory tempDir,
  String fileName,
  String content,
) async {
  final input = io.File('${tempDir.path}/$fileName');
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

  return LynSokSearcher(
    archiveFile: archive,
    indexPath: '${archive.path}.idx.missing',
  );
}

void main() {
  group('LynSokSearcher rawSearch', () {
    test('returns empty results for empty and whitespace-only queries',
        () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final searcher = await _buildSearcherForContent(
          tempDir,
          'doc.txt',
          'A small body with searchable terms.',
        );

        final emptyResults = await searcher.rawSearch('', maxResults: 5);
        final whitespaceResults = await searcher.rawSearch(
          '   \t\n',
          maxResults: 5,
        );

        expect(emptyResults, isEmpty);
        expect(whitespaceResults, isEmpty);
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });

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
        const content = 'ååå test appears after multibyte chars';
        final searcher = await _buildSearcherForContent(
          tempDir,
          'unicode.txt',
          content,
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

    test('collects and orders repeated case-insensitive matches', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final searcher = await _buildSearcherForContent(
          tempDir,
          'repeat.txt',
          'TEST Test test with trailing text',
        );

        final results = await searcher.rawSearch('test', maxResults: 5);
        expect(results, isNotEmpty);

        final first = results.first;
        final ranges = first.matchRanges
            .where((range) => range.term == 'test')
            .toList(growable: false);

        expect(ranges.length, equals(3));
        expect(ranges[0].start, lessThan(ranges[1].start));
        expect(ranges[1].start, lessThan(ranges[2].start));

        for (final range in ranges) {
          expect(
            first.snippet.substring(range.start, range.end).toLowerCase(),
            equals('test'),
          );
        }
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });

    test('context window prefers paragraph boundary around the match', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final searcher = await _buildSearcherForContent(
          tempDir,
          'paragraphs.txt',
          'FIRST_PARAGRAPH_MARKER has unrelated details.\n\n'
          'match appears in second paragraph with useful context.',
        );

        final results = await searcher.rawSearch(
          'match',
          maxResults: 5,
          contextWindowBytes: 30,
        );
        expect(results, isNotEmpty);

        final snippet = results.first.snippet.toLowerCase();
        expect(snippet, contains('match appears in second paragraph'));
        expect(snippet, isNot(contains('first_paragraph_marker')));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });

    test('context window prefers line boundary when paragraph break is absent',
        () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final searcher = await _buildSearcherForContent(
          tempDir,
          'lines.txt',
          'HEADER_LINE_MARKER\nmatch appears on second line with context',
        );

        final results = await searcher.rawSearch(
          'match',
          maxResults: 5,
          contextWindowBytes: 25,
        );
        expect(results, isNotEmpty);

        final snippet = results.first.snippet.toLowerCase();
        expect(snippet, contains('match appears on second line'));
        expect(snippet, isNot(contains('header_line_marker')));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });

    test('context window can align to sentence boundary when no newline exists',
        () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final searcher = await _buildSearcherForContent(
          tempDir,
          'sentences.txt',
          'Intro sentence has background. '
          'Match appears in second sentence for snippet extraction. '
          'Third sentence closes.',
        );

        final results = await searcher.rawSearch(
          'match',
          maxResults: 5,
          contextWindowBytes: 30,
        );
        expect(results, isNotEmpty);

        final snippet = results.first.snippet.toLowerCase();
        expect(snippet, startsWith('match appears in second sentence'));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });

    test('returns full content when document is smaller than context window',
        () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        const content = 'tiny match doc';
        final searcher = await _buildSearcherForContent(
          tempDir,
          'tiny.txt',
          content,
        );

        final results = await searcher.rawSearch(
          'match',
          maxResults: 5,
          contextWindowBytes: 5000,
        );
        expect(results, isNotEmpty);
        expect(results.first.snippet, equals(content));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });

    test('handles matches near the beginning and end of a document', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final searcher = await _buildSearcherForContent(
          tempDir,
          'edges.txt',
          'match at start and some middle content and finally ending with match',
        );

        final startResults = await searcher.rawSearch(
          'match at start',
          maxResults: 5,
          contextWindowBytes: 12,
        );
        expect(startResults, isNotEmpty);
        expect(startResults.first.snippet.toLowerCase(), contains('match'));

        final endResults = await searcher.rawSearch(
          'ending with match',
          maxResults: 5,
          contextWindowBytes: 12,
        );
        expect(endResults, isNotEmpty);
        expect(endResults.first.snippet.toLowerCase(), contains('match'));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });

    test('treats regex special characters in query as literal text',
        () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final searcher = await _buildSearcherForContent(
          tempDir,
          'regex_literal.txt',
          'The exact literal token [abc] appears here once.',
        );

        final results = await searcher.rawSearch('[abc]', maxResults: 5);
        expect(results, isNotEmpty);
        expect(results.first.snippet, contains('[abc]'));

        final abcRanges = results.first.matchRanges
            .where((range) => range.term == 'abc')
            .toList(growable: false);
        expect(abcRanges, isNotEmpty);
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });

    test('context window handles CRLF line boundaries', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_searcher');
      try {
        final searcher = await _buildSearcherForContent(
          tempDir,
          'crlf.txt',
          'HEADER_LINE_MARKER\r\nmatch appears after CRLF boundary',
        );

        final results = await searcher.rawSearch(
          'match',
          maxResults: 5,
          contextWindowBytes: 24,
        );
        expect(results, isNotEmpty);

        final snippet = results.first.snippet.toLowerCase();
        expect(snippet, contains('match appears after crlf boundary'));
        expect(snippet, isNot(contains('header_line_marker')));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // On Windows, temporary files may be locked briefly.
        }
      }
    });
  });

  group('LynSokSearcher indexedSearch', () {
    test('throws StateError when index is not loaded', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_idx');
      try {
        final input = io.File('${tempDir.path}/doc.txt');
        await input.writeAsString('Index loading precondition test.');

        final archive = io.File('${tempDir.path}/archive.lyn');
        final runner = LynSokRunner(
          isolates: 1,
          patterns: const {},
          caseInsensitive: true,
          jsonMode: false,
          compactOutput: archive.path,
          buildIndex: true,
        );
        await runner.run(tempDir.path);

        final searcher = LynSokSearcher(
          archiveFile: archive,
          indexPath: '${archive.path}.idx',
        );

        expect(
          () => searcher.indexedSearch('test', maxResults: 5),
          throwsA(isA<StateError>()),
        );
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('returns empty results for empty and whitespace-only queries',
        () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_idx');
      try {
        final searcher = await _buildSearcherWithIndex(tempDir, {
          'doc.txt': 'A small body with searchable terms.',
        });

        final emptyResults = await searcher.indexedSearch('', maxResults: 5);
        final whitespaceResults = await searcher.indexedSearch(
          '   \t\n',
          maxResults: 5,
        );

        expect(emptyResults, isEmpty);
        expect(whitespaceResults, isEmpty);
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('returns snippet containing the search term', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_idx');
      try {
        final searcher = await _buildSearcherWithIndex(tempDir, {
          'doc.txt': 'This is a test sentence for indexed search checks.',
        });

        final results = await searcher.indexedSearch('test', maxResults: 5);
        expect(results, isNotEmpty);

        final first = results.first;
        expect(first.snippet.toLowerCase(), contains('test'));
        expect(first.snippet, isNot(contains('\x1b[33m')));
        expect(first.snippet, isNot(contains('\x1b[0m')));
        expect(first.matchedTerms, contains('test'));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('snippet matchRanges accurately point to the matched term', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_idx');
      try {
        final searcher = await _buildSearcherWithIndex(tempDir, {
          'doc.txt': 'A sentence where target appears clearly.',
        });

        final results = await searcher.indexedSearch('target', maxResults: 5);
        expect(results, isNotEmpty);

        final first = results.first;
        expect(first.matchRanges, isNotEmpty);
        final ranges = first.matchRanges
            .where((r) => r.term == 'target')
            .toList(growable: false);
        expect(ranges, isNotEmpty);
        final range = ranges.first;
        expect(range.end, greaterThan(range.start));
        expect(
          first.snippet.substring(range.start, range.end).toLowerCase(),
          equals('target'),
        );
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('raw and indexed search agree on the top-ranked document', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_idx');
      try {
        // fruit.txt repeats the term many times; vegetable.txt has it once.
        final searcher = await _buildSearcherWithIndex(tempDir, {
          'fruit.txt': 'mango mango mango fruit fruit fruit',
          'vegetable.txt': 'carrot vegetable greens mango',
        });

        final rawResults = await searcher.rawSearch('mango', maxResults: 5);
        final idxResults =
            await searcher.indexedSearch('mango', maxResults: 5);

        expect(rawResults, isNotEmpty);
        expect(idxResults, isNotEmpty);

        // Both search paths must agree that fruit.txt is the top hit.
        final rawTop =
            rawResults.first.path.split(io.Platform.pathSeparator).last;
        final idxTop =
            idxResults.first.path.split(io.Platform.pathSeparator).last;
        expect(rawTop, equals(idxTop));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('ranks the document with more occurrences higher', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_idx');
      try {
        // a.txt: tf=3 for "apple"; b.txt: tf=1. Same token count so BM25
        // normalization is equal — frequency alone decides the ranking.
        final searcher = await _buildSearcherWithIndex(tempDir, {
          'a.txt': 'apple apple apple padone padtwo',
          'b.txt': 'apple padone padtwo padthree padfour',
        });

        final results = await searcher.indexedSearch('apple', maxResults: 5);
        expect(results.length, equals(2));
        expect(
          results.first.path.split(io.Platform.pathSeparator).last,
          equals('a.txt'),
        );
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('ranks the document with more occurrences higher, long text documents', () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_idx');
      try {
        // a.txt: tf=3 for "apple"; b.txt: tf=1. Same token count so BM25
        // normalization is equal — frequency alone decides the ranking.
        final searcher = await _buildSearcherWithIndex(tempDir, {
          'a.txt': 'apple apple apple padone padtwo padthree padfour padfive padsix padseven padeight padnine padten',
          'b.txt': 'apple padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen',
          'c.txt': 'padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen, the quick brown fox jumps over the lazy dog, apple padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen, apple padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen, apple, this is a test sentence, this is just a test, padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen, this is a test sentence, this is just a test, apple, padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen, this is a test sentence, this is just a test, apple, this is a test sentence, this is just a test, apple, this is a test sentence, this is just a test, this is a long document with many occurrences of the word apple, padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen',
          'd.txt': 'padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven padtwelve padthirteen padfourteen padfifteen padone padtwo padthree padfour padfive padsix padseven padeight padnine padten padeleven apple padtwelve padthirteen padfourteen padfifteen',
        });

        final results = await searcher.indexedSearch('apple', maxResults: 5);
        expect(results.length, equals(4));
        expect(
          results.first.path.split(io.Platform.pathSeparator).last,
          equals('a.txt'),
        );
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('proximity boost ranks document with closer term pair higher',
        () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_idx');
      try {
        // Both docs: 10 tokens, tf=1 for "alpha" and "beta" -> identical BM25.
        // close.txt: alpha and beta are adjacent (byte distance ~= 6).
        // far.txt:   alpha and beta are at opposite ends (byte distance ~= 46).
        // Proximity boost: 1/(1+ln(1+d)); smaller d -> larger boost -> ranks first.
        final searcher = await _buildSearcherWithIndex(tempDir, {
          'close.txt': 'alpha beta pad1 pad2 pad3 pad4 pad5 pad6 pad7 pad8',
          'far.txt': 'alpha pad1 pad2 pad3 pad4 pad5 pad6 pad7 pad8 beta',
        });

        final results = await searcher.indexedSearch(
          'alpha beta',
          maxResults: 5,
        );
        expect(results.length, equals(2));
        expect(
          results.first.path.split(io.Platform.pathSeparator).last,
          equals('close.txt'),
        );
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('respects maxResults and score ordering for indexed ranking',
        () async {
      final tempDir = io.Directory.systemTemp.createTempSync('lynsok_idx');
      try {
        final searcher = await _buildSearcherWithIndex(tempDir, {
          'high.txt': 'apple apple apple filler one two three',
          'mid.txt': 'apple apple filler one two three four',
          'low.txt': 'apple filler one two three four five',
        });

        final results = await searcher.indexedSearch('apple', maxResults: 2);
        expect(results.length, equals(2));

        final ranked = results
            .map((r) => r.path.split(io.Platform.pathSeparator).last)
            .toList(growable: false);
        expect(ranked, equals(['high.txt', 'mid.txt']));
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });
  });
}
