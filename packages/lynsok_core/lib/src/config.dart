import 'dart:convert';
import 'dart:io';

/// Configuration used by the CLI, MCP server, REST server, and Flutter UI.
///
/// Stored as JSON (default file name: `.lynsok.json`).
class LynSokConfig {
  /// Path to the `.lyn` archive.
  final String? lynPath;

  /// Path to an optional `.idx` index file.
  final String? indexPath;

  /// Which port the REST server should listen on.
  final int restPort;

  /// LLM provider settings.
  final LlmConfig llm;

  LynSokConfig({
    this.lynPath,
    this.indexPath,
    this.restPort = 8181,
    LlmConfig? llm,
  }) : llm = llm ?? LlmConfig();

  factory LynSokConfig.fromJson(Map<String, dynamic> json) {
    return LynSokConfig(
      lynPath: json['lynPath'] as String?,
      indexPath: json['indexPath'] as String?,
      restPort: json['restPort'] is int ? json['restPort'] as int : 8181,
      llm: json['llm'] is Map<String, dynamic>
          ? LlmConfig.fromJson(json['llm'] as Map<String, dynamic>)
          : LlmConfig(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (lynPath != null) 'lynPath': lynPath,
        if (indexPath != null) 'indexPath': indexPath,
        'restPort': restPort,
        'llm': llm.toJson(),
      };

  static Future<LynSokConfig> load([String? path]) async {
    final configFile = File(path ?? '.lynsok.json');
    if (!configFile.existsSync()) {
      return LynSokConfig();
    }
    final content = await configFile.readAsString();
    try {
      final jsonMap = jsonDecode(content) as Map<String, dynamic>;
      return LynSokConfig.fromJson(jsonMap);
    } catch (_) {
      return LynSokConfig();
    }
  }

  Future<void> save([String? path]) async {
    final configFile = File(path ?? '.lynsok.json');
    await configFile.writeAsString(JsonEncoder.withIndent('  ').convert(toJson()));
  }
}

class LlmConfig {
  /// Provider name, e.g. "openai", "ollama", "gemini".
  final String provider;

  /// Optional API key (may also come from environment variables).
  final String? apiKey;

  /// Model name (e.g. "gpt-4o", "llama2", "vicuna").
  final String model;

  /// System prompt or role description.
  final String systemPrompt;

  LlmConfig({
    this.provider = 'openai',
    this.apiKey,
    this.model = 'gpt-4o',
    this.systemPrompt =
        'You are a helpful assistant. Use the provided context to answer the user query.',
  });

  factory LlmConfig.fromJson(Map<String, dynamic> json) {
    return LlmConfig(
      provider: json['provider'] as String? ?? 'openai',
      apiKey: json['apiKey'] as String?,
      model: json['model'] as String? ?? 'gpt-4o',
      systemPrompt: json['systemPrompt'] as String?
          ??
          'You are a helpful assistant. Use the provided context to answer the user query.',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      if (apiKey != null) 'apiKey': apiKey,
      'model': model,
      'systemPrompt': systemPrompt,
    };
  }
}
