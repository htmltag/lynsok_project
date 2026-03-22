import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:lynsok_core/lynsok_runner.dart';
import 'package:lynsok_core/src/utils/lyn_reader.dart';

Future<void> main(List<String> args) async {
  final startTime = DateTime.now();

  // Some users invoke as `dart run bin/lynsok.dart lynsok search ...`.
  // Normalize that to the real subcommand.
  final normalizedArgs = (args.isNotEmpty && args[0] == 'lynsok')
      ? args.sublist(1)
      : args;

  // Subcommand support: `lynsok search ...`
  if (normalizedArgs.isNotEmpty && normalizedArgs[0] == 'search') {
    await _runSearchCommand(normalizedArgs.sublist(1));
    return;
  }

  final parser = ArgParser()
    ..addOption(
      'path',
      abbr: 'f',
      help: 'Path to the file or directory to process (use `-` for stdin)',
    )
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to a JSON config file (default: .lynsok.json)',
      valueHelp: 'file',
    )
    ..addOption(
      'max-processors',
      abbr: 'm',
      help:
          'Maximum number of processors to use (default: system processors - 1)',
      valueHelp: 'number',
    )
    ..addOption(
      'lyn-output',
      abbr: 'o',
      help: 'Generate a LynSok Binary Archive at the given path',
      valueHelp: 'file',
    )
    ..addOption(
      'index-output',
      abbr: 'I',
      help:
          'Write a search index for the archive to this file (default: <lyn-output>.idx)',
      valueHelp: 'file',
    )
    ..addFlag(
      'build-index',
      abbr: 'x',
      help: 'Build a search index during compaction (requires --lyn-output)',
      defaultsTo: false,
    )
    ..addOption(
      'json-output',
      abbr: 'j',
      help: 'Write newline-delimited JSON records (requires --lyn-output)',
      valueHelp: 'file',
    )
    ..addOption(
      'mode',
      abbr: 'M',
      help: 'Force mode: "search" (pattern counting) or "compact" (lyn)',
      allowed: ['search', 'compact'],
    );
  parser.addMultiOption(
    'pattern',
    abbr: 'p',
    help:
        'Search pattern(s) to match (can be used multiple times). Leave empty to enable JSON search mode.',
    valueHelp: 'text',
  );
  parser.addFlag(
    'case-insensitive',
    abbr: 'i',
    help: 'Perform case-insensitive search (default: true)',
    defaultsTo: true,
  );
  parser.addFlag(
    'verbose',
    abbr: 'v',
    help: 'Print additional diagnostic information',
    defaultsTo: false,
  );
  parser.addFlag(
    'help',
    abbr: 'h',
    help: 'Show this help message',
    negatable: false,
    defaultsTo: false,
  );

  final results = parser.parse(args);
  final configPath = results['config'] as String?;
  final config = await LynSokConfig.load(configPath);

  String? path = results['path'] as String?;
  final lynOutput = (results['lyn-output'] as String?) ?? config.lynPath;
  final indexOutput = (results['index-output'] as String?) ?? config.indexPath;
  final buildIndex = results['build-index'] as bool;
  final jsonOutput = results['json-output'] as String?;
  final forcedMode = results['mode'] as String?;
  final verbose = results['verbose'] as bool;
  final help = results['help'] as bool;

  // Use config defaults only when CLI options are missing.
  path ??= config.lynPath;

  if (help) {
    stdout.writeln('Usage: lynsok -f <path> [options]');
    stdout.writeln(parser.usage);
    return;
  }

  if (path == null) {
    stderr.writeln('Error: missing required --path (-f)');
    stderr.writeln(parser.usage);
    exit(2);
  }
  if (path == '-') {
    // read stdin into temporary file
    final temp = File(
      '${Directory.systemTemp.path}/lynsok_stdin_${DateTime.now().millisecondsSinceEpoch}',
    );
    final sink = temp.openWrite();
    await stdin.transform(utf8.decoder).forEach(sink.write);
    await sink.flush();
    await sink.close();
    path = temp.path;
    if (verbose) stdout.writeln('read stdin into $path');
  }

  if (lynOutput != null && Directory(lynOutput).existsSync()) {
    stderr.writeln('Error: --lyn-output must be a file path, not a directory');
    exit(2);
  }
  if (jsonOutput != null && lynOutput == null) {
    stderr.writeln('Error: --json-output requires --lyn-output');
    exit(2);
  }

  final isolates = _parseIsolates(results['max-processors'] as String?);

  // determine modes
  bool compactMode = lynOutput != null;
  if (forcedMode == 'compact') compactMode = true;
  if (forcedMode == 'search') compactMode = false;

  final patternArgs = results['pattern'] as List<String>;
  bool jsonMode = patternArgs.isEmpty;
  if (forcedMode == 'search') jsonMode = true;
  if (forcedMode == 'compact') jsonMode = false;

  final patterns = <String, Uint8List>{};
  if (!jsonMode && !compactMode) {
    for (final patternStr in patternArgs) {
      patterns[patternStr] = Uint8List.fromList(utf8.encode(patternStr));
    }
  }

  final caseInsensitive = results['case-insensitive'] as bool;
  await LynSokRunner(
    isolates: isolates,
    patterns: patterns,
    caseInsensitive: caseInsensitive,
    jsonMode: jsonMode,
    compactOutput: lynOutput,
    buildIndex: buildIndex,
    indexOutput: indexOutput,
    verbose: verbose,
  ).run(path);

  // if requested, convert the archive to JSON lines
  if (jsonOutput != null && lynOutput != null) {
    final records = await parseLyn(File(lynOutput));
    final outSink = File(jsonOutput).openWrite();
    for (var r in records) {
      final line = jsonEncode({
        'path': r['path'],
        'text': utf8.decode(r['body'] as Uint8List),
      });
      outSink.writeln(line);
    }
    await outSink.flush();
    await outSink.close();
    if (verbose) {
      stdout.writeln('Wrote ${records.length} JSON records to $jsonOutput');
    }
  }

  final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000;
  stdout.writeln('Total execution time: ${elapsed.toStringAsFixed(2)} seconds');
}

Future<void> _runSearchCommand(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'lyn',
      abbr: 'i',
      help: 'Path to a .lyn archive to search',
      valueHelp: 'file',
    )
    ..addOption(
      'index',
      abbr: 'I',
      help: 'Path to the index file (defaults to <lyn>.idx)',
      valueHelp: 'file',
    )
    ..addOption(
      'query',
      abbr: 'q',
      help: 'Query string to search for',
      valueHelp: 'text',
    )
    ..addOption(
      'max-results',
      abbr: 'n',
      help: 'Maximum number of results to return',
      valueHelp: 'number',
      defaultsTo: '10',
    )
    ..addOption(
      'context-window',
      abbr: 'w',
      help:
          'Size of the context window (in bytes) used to build the snippet around the match',
      valueHelp: 'bytes',
      defaultsTo: '1200',
    )
    ..addFlag(
      'rag',
      abbr: 'R',
      help:
          'Output a single bundled RAG context block containing the top results snippets',
      defaultsTo: false,
    )
    ..addOption(
      'rag-separator',
      help:
          'Separator string used between context fragments when --rag is enabled',
      defaultsTo: '\n\n-----\n\n',
      valueHelp: 'text',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Print additional diagnostic information',
      defaultsTo: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help message',
      negatable: false,
      defaultsTo: false,
    );

  final results = parser.parse(args);
  final help = results['help'] as bool;
  if (help) {
    stdout.writeln(
      'Usage: lynsok search --lyn <file> --query "term" [options]',
    );
    stdout.writeln(parser.usage);
    return;
  }

  final lynPath = results['lyn'] as String?;
  final query = results['query'] as String?;
  final maxResults = int.tryParse(results['max-results'] as String) ?? 10;
  final contextWindow =
      int.tryParse(results['context-window'] as String) ?? 1200;
  final ragEnabled = results['rag'] as bool;
  final ragSeparator = results['rag-separator'] as String;
  final verbose = results['verbose'] as bool;

  if (lynPath == null || query == null) {
    stderr.writeln('Error: --lyn and --query are required for search.');
    stderr.writeln(parser.usage);
    exit(2);
  }

  final lynFile = File(lynPath);
  if (!lynFile.existsSync()) {
    stderr.writeln('Error: LYN file not found: $lynPath');
    exit(2);
  }

  String? indexPath = results['index'] as String?;
  indexPath ??= '$lynPath.idx';

  final indexFile = File(indexPath);
  final searcher = LynSokSearcher(archiveFile: lynFile, indexPath: indexPath);

  List<SearchResult> resultsList;
  final sw = Stopwatch()..start();

  if (indexFile.existsSync()) {
    if (verbose) stdout.writeln('Index found at $indexPath. Loading...');
    final loadStart = sw.elapsedMilliseconds;
    await searcher.loadIndex();
    if (verbose)
      stdout.writeln(
        'Index loaded in ${(sw.elapsedMilliseconds - loadStart)}ms',
      );

    if (verbose) stdout.writeln('Performing indexed search for "$query"...');
    resultsList = await searcher.indexedSearch(
      query,
      maxResults: maxResults,
      contextWindowBytes: contextWindow,
    );
    if (verbose)
      stdout.writeln('Search completed in ${sw.elapsedMilliseconds}ms (total)');
  } else {
    stderr.writeln(
      'Warning: index file not found at $indexPath; falling back to raw scan.',
    );
    if (verbose) stdout.writeln('Starting raw scan (this may be slow)...');
    resultsList = await searcher.rawSearch(
      query,
      maxResults: maxResults,
      contextWindowBytes: contextWindow,
    );
    if (verbose)
      stdout.writeln('Raw scan completed in ${sw.elapsedMilliseconds}ms');
  }

  if (ragEnabled) {
    // Bundle all top snippets into a single RAG context block.
    final parts = resultsList
        .map(
          (r) =>
              'path: ${r.path}\nscore: ${r.score.toStringAsFixed(3)}\n\n${r.snippet}',
        )
        .toList();
    stdout.write(parts.join(ragSeparator));
    stdout.writeln();
  } else {
    for (var r in resultsList) {
      stdout.writeln('---');
      stdout.writeln('path: ${r.path}');
      stdout.writeln('score: ${r.score.toStringAsFixed(3)}');
      stdout.writeln('snippet: ${r.snippet}');
    }
  }
}

// Parses the max-processors argument, applying defaults and validation.
int _parseIsolates(String? maxProcessorsArg) {
  if (maxProcessorsArg == null) {
    return (Platform.numberOfProcessors - 1).clamp(
      1,
      Platform.numberOfProcessors,
    );
  }

  try {
    final isolates = int.parse(maxProcessorsArg);
    if (isolates <= 0) {
      stderr.writeln('Error: max-processors must be greater than 0');
      exit(2);
    }
    if (isolates > Platform.numberOfProcessors) {
      stderr.writeln(
        'Warning: max-processors ($isolates) exceeds available processors (${Platform.numberOfProcessors}). Using ${Platform.numberOfProcessors}.',
      );
      return Platform.numberOfProcessors;
    }
    stderr.writeln('Using $isolates processor(s) for processing.');
    return isolates;
  } catch (e) {
    stderr.writeln('Error: max-processors must be a valid integer');
    exit(2);
  }
}
