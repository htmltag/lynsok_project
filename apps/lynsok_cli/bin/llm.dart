import 'dart:convert';
import 'dart:io';

import 'package:lynsok_core/lynsok_runner.dart';

/// Generates an LLM response using search results as context.
///
/// Example:
///
/// dart run bin/llm.dart --question "What is the main topic?" --lyn corpus.lyn

Future<void> main(List<String> args) async {
  final config = await LynSokConfig.load();

  final lynPath = config.lynPath ?? _argValue(args, '--lyn');
  final indexPath = config.indexPath ?? _argValue(args, '--index');
  final question = _argValue(args, '--question') ?? _argValue(args, '--q');
  final maxResults = int.tryParse(_argValue(args, '--max-results') ?? '5') ?? 5;
  final contextWindow =
      int.tryParse(_argValue(args, '--context-window') ?? '1200') ?? 1200;

  if (lynPath == null || question == null) {
    stderr.writeln(
      'Usage: llm.dart --lyn <file> --question "..." [--max-results N]',
    );
    exit(2);
  }

  final archiveFile = File(lynPath);
  if (!archiveFile.existsSync()) {
    stderr.writeln('Error: LYN file not found: $lynPath');
    exit(2);
  }

  final indexPathStr = indexPath ?? '$lynPath.idx';
  final indexFile = File(indexPathStr);
  final searcher = LynSokSearcher(
    archiveFile: archiveFile,
    indexPath: indexPathStr,
  );
  if (indexFile.existsSync()) {
    await searcher.loadIndex();
  }

  final results = await searcher.indexedSearch(
    question,
    maxResults: maxResults,
    contextWindowBytes: contextWindow,
  );

  final context = results.map((r) => r.snippet).join('\n\n-----\n\n');

  final llm = LlmClient.fromConfig(config.llm);
  final response = await llm.generate(
    systemPrompt: config.llm.systemPrompt,
    userPrompt:
        'Use the context below to answer the question:\n\n$context\n\nQuestion: $question',
    maxTokens: 512,
  );

  final out = {'question': question, 'context': context, 'answer': response};

  stdout.writeln(jsonEncode(out));
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index != -1 && index + 1 < args.length) {
    return args[index + 1];
  }
  return null;
}
