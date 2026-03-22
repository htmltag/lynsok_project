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

  const IndexingState({
    this.isIndexing = false,
    this.progress = 0.0,
    this.currentFile = '',
    this.error,
  });

  IndexingState copyWith({
    bool? isIndexing,
    double? progress,
    String? currentFile,
    String? error,
  }) {
    return IndexingState(
      isIndexing: isIndexing ?? this.isIndexing,
      progress: progress ?? this.progress,
      currentFile: currentFile ?? this.currentFile,
      error: error,
    );
  }
}

class IndexingNotifier extends StateNotifier<IndexingState> {
  IndexingNotifier() : super(const IndexingState());

  Future<void> startIndexing(
    String sourcePath,
    String lynPath, {
    List<String> excludePatterns = const [],
  }) async {
    state = state.copyWith(
      isIndexing: true,
      progress: 0.0,
      currentFile: '',
      error: null,
    );

    try {
      final runner = LynSokRunner(
        isolates: 4,
        patterns: {},
        caseInsensitive: true,
        compactOutput: lynPath,
        buildIndex: true,
        indexOutput: '$lynPath.idx',
        verbose: true,
      );

      await runner.run(sourcePath);

      state = state.copyWith(isIndexing: false, progress: 1.0);
    } catch (e) {
      state = state.copyWith(isIndexing: false, error: e.toString());
    }
  }
}
