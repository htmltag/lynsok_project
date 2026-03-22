import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop/models/index_model.dart';
import 'package:desktop/providers/index_provider.dart';
import 'package:desktop/providers/lynsok_provider.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class IndexCreationWizard extends ConsumerStatefulWidget {
  const IndexCreationWizard({super.key});

  @override
  ConsumerState<IndexCreationWizard> createState() =>
      _IndexCreationWizardState();
}

class _IndexCreationWizardState extends ConsumerState<IndexCreationWizard> {
  int _currentStep = 0;
  String? _selectedPath;
  final List<String> _excludePatterns = [
    '.git',
    'node_modules',
    'build',
    '.DS_Store',
  ];
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Index'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _onStepCancel,
        steps: [
          Step(
            title: const Text('Select Source Folder'),
            content: _buildStep1(),
            isActive: _currentStep >= 0,
          ),
          Step(
            title: const Text('Configure Index'),
            content: _buildStep2(),
            isActive: _currentStep >= 1,
          ),
          Step(
            title: const Text('Create Index'),
            content: _buildStep3(),
            isActive: _currentStep >= 2,
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose the folder containing documents to index:'),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _pickFolder,
          icon: const Icon(Icons.folder_open),
          label: const Text('Select Folder'),
        ),
        if (_selectedPath != null) ...[
          const SizedBox(height: 16),
          Text('Selected: $_selectedPath'),
        ],
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Index Name',
            hintText: 'Enter a name for this index',
          ),
        ),
        const SizedBox(height: 16),
        const Text('Exclude patterns:'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _excludePatterns.map((pattern) {
            return Chip(
              label: Text(pattern),
              onDeleted: () {
                setState(() {
                  _excludePatterns.remove(pattern);
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Add exclude pattern (e.g., *.tmp)',
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty && !_excludePatterns.contains(value)) {
              setState(() {
                _excludePatterns.add(value);
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildStep3() {
    final indexingState = ref.watch(indexingProvider);

    if (indexingState.isIndexing) {
      return Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Indexing: ${indexingState.currentFile}'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: indexingState.progress),
          Text('${(indexingState.progress * 100).toInt()}%'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ready to create index.'),
        const SizedBox(height: 16),
        Text('Name: ${_nameController.text}'),
        Text('Source: $_selectedPath'),
        Text('Excludes: ${_excludePatterns.join(', ')}'),
      ],
    );
  }

  void _onStepContinue() {
    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
    } else {
      _createIndex();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _selectedPath = result;
        if (_nameController.text.isEmpty) {
          _nameController.text = path.basename(result);
        }
      });
    }
  }

  Future<void> _createIndex() async {
    if (_selectedPath == null || _nameController.text.isEmpty) return;

    final appDir = await getApplicationDocumentsDirectory();
    final lynPath = '${appDir.path}/${_nameController.text}.lyn';

    final index = IndexModel(
      name: _nameController.text,
      sourcePath: _selectedPath!,
      lynPath: lynPath,
      indexPath: '$lynPath.idx',
      excludePatterns: _excludePatterns,
      createdAt: DateTime.now(),
    );

    // Add to database first
    await ref.read(indexProvider.notifier).addIndex(index);

    // Start indexing
    await ref
        .read(indexingProvider.notifier)
        .startIndexing(
          _selectedPath!,
          lynPath,
          excludePatterns: _excludePatterns,
        );

    // Navigate back to dashboard
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
