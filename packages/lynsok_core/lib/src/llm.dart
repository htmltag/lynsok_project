import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

/// A minimal interface for LLM providers.
abstract class LlmClient {
  Future<String> generate({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens,
  });

  factory LlmClient.fromConfig(LlmConfig config) {
    switch (config.provider.toLowerCase()) {
      case 'ollama':
        return OllamaClient(config);
      case 'openai':
      default:
        return OpenAiClient(config);
    }
  }
}

class OpenAiClient implements LlmClient {
  final LlmConfig config;
  final http.Client _http = http.Client();

  OpenAiClient(this.config);

  @override
  Future<String> generate({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 512,
  }) async {
    final apiKey = config.apiKey ?? Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null) {
      throw StateError('OpenAI API key not set (config.apiKey or OPENAI_API_KEY)');
    }

    final body = {
      'model': config.model,
      'max_tokens': maxTokens,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    };

    final response = await _http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw StateError('OpenAI request failed: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choice = (data['choices'] as List<dynamic>?)?.firstOrNull;
    if (choice == null) {
      throw StateError('Unexpected OpenAI response: ${response.body}');
    }
    return (choice['message'] as Map<String, dynamic>)['content'] as String;
  }
}

class OllamaClient implements LlmClient {
  final LlmConfig config;
  final http.Client _http = http.Client();

  OllamaClient(this.config);

  @override
  Future<String> generate({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 512,
  }) async {
    final baseUrl = Platform.environment['OLLAMA_URL'] ?? 'http://127.0.0.1:11434';
    final model = config.model;

    final body = {
      'model': model,
      'prompt': {
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      },
      'max_tokens': maxTokens,
    };

    final response = await _http.post(
      Uri.parse('$baseUrl/v1/chat/completions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw StateError('Ollama request failed: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choice = (data['choices'] as List<dynamic>?)?.firstOrNull;
    if (choice == null) {
      throw StateError('Unexpected Ollama response: ${response.body}');
    }
    return (choice['message'] as Map<String, dynamic>)['content'] as String;
  }
}

extension _FirstOrNullExtension<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : this[0];
}
