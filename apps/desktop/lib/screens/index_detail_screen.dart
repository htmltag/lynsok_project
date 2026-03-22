import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop/models/index_model.dart';
import 'package:desktop/providers/lynsok_provider.dart';
import 'package:clipboard/clipboard.dart';
import 'package:lynsok_core/lynsok_runner.dart';

class IndexDetailScreen extends ConsumerStatefulWidget {
  final IndexModel index;

  const IndexDetailScreen({super.key, required this.index});

  @override
  ConsumerState<IndexDetailScreen> createState() => _IndexDetailScreenState();
}

class _IndexDetailScreenState extends ConsumerState<IndexDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  String _selectedLlm = 'ollama';
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _promptController.text =
        'You are a helpful assistant with access to local documents.';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.index.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Search & RAG'),
            Tab(text: 'Connectivity'),
            Tab(text: 'Maintenance'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSearchTab(),
          _buildConnectivityTab(),
          _buildMaintenanceTab(),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Enter search query...',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _performSearch,
              ),
            ),
            onSubmitted: (_) => _performSearch(),
          ),
          const SizedBox(height: 16),

          // Results list
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(child: Text('No results yet'))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];
                      return ListTile(
                        title: Text(result['title'] ?? 'Document'),
                        subtitle: Text(
                          result['snippet'] ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          // TODO: Open document viewer
                        },
                      );
                    },
                  ),
          ),

          // RAG Panel
          const Divider(),
          const Text(
            'RAG Configuration',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // LLM Dropdown
          DropdownButtonFormField<String>(
            initialValue: _selectedLlm,
            decoration: const InputDecoration(labelText: 'LLM Provider'),
            items: const [
              DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
              DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
            ],
            onChanged: (value) {
              setState(() {
                _selectedLlm = value!;
              });
            },
          ),

          const SizedBox(height: 8),

          // System Prompt Editor
          TextField(
            controller: _promptController,
            decoration: const InputDecoration(
              labelText: 'System Prompt',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),

          const SizedBox(height: 16),

          // Ask AI Button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _askAI,
              icon: const Icon(Icons.smart_toy),
              label: const Text('Ask AI'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectivityTab() {
    final config = ref.watch(configProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HTTP Server
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'HTTP Server',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Switch(
                        value: widget.index.serverActive,
                        onChanged: (value) {
                          // TODO: Toggle HTTP server
                        },
                      ),
                    ],
                  ),
                  if (widget.index.serverActive) ...[
                    const SizedBox(height: 8),
                    Text('Running on port ${config?.restPort ?? 8181}'),
                    Text(
                      'Endpoint: http://localhost:${config?.restPort ?? 8181}/search',
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // MCP Server
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'MCP Server',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Switch(
                        value: false, // TODO: MCP server status
                        onChanged: (value) {
                          // TODO: Toggle MCP server
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Model Context Protocol for LLM integration'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Config Helper
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LLM Configuration',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Copy this configuration for Claude/Cursor:'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(_generateConfigJson()),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        FlutterClipboard.copy(_generateConfigJson());
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Configuration copied to clipboard',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy to Clipboard'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Index Statistics',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Source Path: ${widget.index.sourcePath}'),
                  Text('File Count: ${widget.index.fileCount}'),
                  Text('Total Size: ${widget.index.totalSize}'),
                  Text('Created: ${widget.index.createdAt}'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Actions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Actions',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _reindex,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-index'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _deleteIndex,
                      icon: const Icon(Icons.delete, color: Colors.white),
                      label: const Text('Delete Index'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _performSearch() async {
    if (_searchController.text.isEmpty) return;

    try {
      final archiveFile = File(
        widget.index.indexPath.replaceAll(RegExp(r'\.idx$'), '.lyn'),
      );
      final searcher = LynSokSearcher(
        archiveFile: archiveFile,
        indexPath: widget.index.indexPath,
      );
      if (File(widget.index.indexPath).existsSync()) {
        await searcher.loadIndex();
      }
      final results = await searcher.indexedSearch(
        _searchController.text,
        maxResults: 10,
        contextWindowBytes: 200,
      );

      setState(() {
        _searchResults = results.map((result) {
          return {
            'title': result.path.split('/').last,
            'snippet': result.snippet,
            'path': result.path,
            'score': result.score,
          };
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    }
  }

  void _askAI() async {
    if (_searchResults.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please perform a search first')),
        );
      }
      return;
    }

    final llmConfig = ref.read(configProvider);
    if (llmConfig == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('LLM configuration not found')),
        );
      }
      return;
    }

    try {
      final client = LlmClient.fromConfig(llmConfig.llm);

      // Build context from top 3 results
      final contextText = _searchResults
          .take(3)
          .map((result) {
            return '${result['title']}: ${result['snippet']}';
          })
          .join('\n\n');

      final userPrompt =
          'Context:\n$contextText\n\nQuestion: ${_searchController.text}';

      final response = await client.generate(
        systemPrompt: _promptController.text,
        userPrompt: userPrompt,
        maxTokens: 1000,
      );

      // Show response in dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('AI Response'),
            content: SingleChildScrollView(child: Text(response)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('AI request failed: $e')));
      }
    }
  }

  String _generateConfigJson() {
    return '''
{
  "mcpServers": {
    "lynsok": {
      "command": "lynsok",
      "args": ["mcp", "--index", "${widget.index.lynPath}"],
      "env": {}
    }
  }
}
''';
  }

  void _reindex() {
    // TODO: Implement re-indexing
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Re-indexing functionality coming soon')),
      );
    }
  }

  void _deleteIndex() {
    // TODO: Implement delete with confirmation
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Index'),
          content: const Text(
            'Are you sure you want to delete this index? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                // TODO: Delete files and remove from DB
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Back to dashboard
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
  }
}
