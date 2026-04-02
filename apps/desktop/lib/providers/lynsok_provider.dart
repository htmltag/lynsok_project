import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lynsok_core/lynsok_runner.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';

// Provider for LynSokConfig
final configProvider = StateNotifierProvider<ConfigNotifier, LynSokConfig?>((
  ref,
) {
  return ConfigNotifier();
});

typedef SearcherKey = ({String lynPath, String indexPath});

// Cached searcher per archive/index path pair.
// This keeps the loaded index in memory and avoids repeated JSON load/parse
// on every query from the desktop Search tab.
final cachedSearcherProvider =
    FutureProvider.family<LynSokSearcher, SearcherKey>((ref, key) async {
      final searcher = LynSokSearcher(
        archiveFile: File(key.lynPath),
        indexPath: key.indexPath,
      );

      if (File(key.indexPath).existsSync()) {
        await searcher.loadIndex();
      }

      return searcher;
    });

class ConfigNotifier extends StateNotifier<LynSokConfig?> {
  ConfigNotifier() : super(null) {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final configPath = '${appDir.path}/.lynsok.json';

      if (await File(configPath).exists()) {
        state = await LynSokConfig.load(configPath);
      } else {
        // Create default config
        state = LynSokConfig(
          lynPath: '',
          indexPath: '',
          restPort: 8181,
          llm: LlmConfig(
            provider: 'ollama',
            model: 'llama3.2',
            systemPrompt:
                'You are a helpful assistant with access to local documents.',
          ),
        );
        await state!.save(configPath);
      }
    } catch (e) {
      // Handle error, maybe set default
      state = LynSokConfig(
        lynPath: '',
        indexPath: '',
        restPort: 8181,
        llm: LlmConfig(
          provider: 'ollama',
          model: 'llama3.2',
          systemPrompt:
              'You are a helpful assistant with access to local documents.',
        ),
      );
    }
  }

  Future<void> updateConfig(LynSokConfig newConfig) async {
    state = newConfig;
    final appDir = await getApplicationDocumentsDirectory();
    final configPath = '${appDir.path}/.lynsok.json';
    await newConfig.save(configPath);
  }
}

// Provider for indexing operations
final indexingProvider = StateNotifierProvider<IndexingNotifier, IndexingState>(
  (ref) {
    return IndexingNotifier();
  },
);

class IndexingState {
  final bool isIndexing;
  final double progress;
  final String currentFile;
  final String? error;
  final List<String> outputLines;

  const IndexingState({
    this.isIndexing = false,
    this.progress = 0.0,
    this.currentFile = '',
    this.error,
    this.outputLines = const [],
  });

  IndexingState copyWith({
    bool? isIndexing,
    double? progress,
    String? currentFile,
    String? error,
    List<String>? outputLines,
  }) {
    return IndexingState(
      isIndexing: isIndexing ?? this.isIndexing,
      progress: progress ?? this.progress,
      currentFile: currentFile ?? this.currentFile,
      error: error,
      outputLines: outputLines ?? this.outputLines,
    );
  }
}

class IndexingNotifier extends StateNotifier<IndexingState> {
  IndexingNotifier() : super(const IndexingState());

  static const int _maxOutputLines = 400;

  void _appendOutputLine(List<String> outputLines, String line) {
    outputLines.add(line);
    if (outputLines.length > _maxOutputLines) {
      outputLines.removeRange(0, outputLines.length - _maxOutputLines);
    }
    state = state.copyWith(outputLines: List<String>.from(outputLines));
  }

  Future<void> startIndexing(
    String sourcePath,
    String lynPath, {
    List<String> excludePatterns = const [],
  }) async {
    final outputLines = <String>[
      '\$ lynsok index --source "$sourcePath"',
      'Starting indexing process...',
      '',
      'Source directory: $sourcePath',
      'Output archive: $lynPath',
      'Build index: true',
      'Verbose mode: true',
      '',
    ];

    state = state.copyWith(
      isIndexing: true,
      progress: 0.0,
      currentFile: '',
      error: null,
      outputLines: List<String>.from(outputLines),
    );

    try {
      // Run the actual indexing
      final runner = LynSokRunner(
        isolates: 4,
        patterns: {},
        caseInsensitive: true,
        compactOutput: lynPath,
        buildIndex: true,
        indexOutput: '$lynPath.idx',
        verbose: true,
        onLog: (line) {
          _appendOutputLine(outputLines, line);
        },
      );

      await runner.run(sourcePath);

      // Add completion message
      _appendOutputLine(outputLines, '');
      _appendOutputLine(outputLines, 'Index creation completed successfully!');
      _appendOutputLine(outputLines, 'Archive: $lynPath');
      _appendOutputLine(outputLines, 'Index: $lynPath.idx');

      state = state.copyWith(
        isIndexing: false,
        progress: 1.0,
        outputLines: List<String>.from(outputLines),
      );
    } catch (e) {
      _appendOutputLine(outputLines, '');
      _appendOutputLine(outputLines, 'ERROR: ${e.toString()}');
      state = state.copyWith(
        isIndexing: false,
        error: e.toString(),
        outputLines: List<String>.from(outputLines),
      );
    }
  }
}
