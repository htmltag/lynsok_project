import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop/models/index_model.dart';
import 'package:desktop/providers/index_provider.dart';
import 'package:desktop/providers/lynsok_provider.dart';
import 'package:path/path.dart' as path;

class IndexCreationWizard extends ConsumerStatefulWidget {
  const IndexCreationWizard({super.key});

  @override
  ConsumerState<IndexCreationWizard> createState() =>
      _IndexCreationWizardState();
}

class _IndexCreationWizardState extends ConsumerState<IndexCreationWizard> {
  int _currentStep = 0;
  String? _selectedPath;
  String? _outputLynPath;
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
        const SizedBox(height: 10),
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
        const SizedBox(height: 16),
        const Text('Index output file (.lyn):'),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _pickOutputFile,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Choose Output File'),
        ),
        if (_outputLynPath != null) ...[
          const SizedBox(height: 8),
          Text('Output: $_outputLynPath'),
        ],
      ],
    );
  }

  Widget _buildStep3() {
    final indexingState = ref.watch(indexingProvider);

    final displayLines = indexingState.outputLines.isEmpty
        ? indexingState.isIndexing
              ? const [
                  'Starting indexing process...',
                  '',
                  '(Waiting for output...)',
                ]
              : const ['Terminal output will appear here when indexing starts.']
        : indexingState.outputLines.length > 8
        ? indexingState.outputLines.sublist(
            indexingState.outputLines.length - 8,
          )
        : indexingState.outputLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          indexingState.isIndexing
              ? 'Indexing in progress...'
              : 'Ready to create index.',
        ),
        const SizedBox(height: 16),
        Text('Name: ${_nameController.text}'),
        Text('Source: $_selectedPath'),
        Text('Output (.lyn): ${_outputLynPath ?? '(not selected)'}'),
        Text(
          'Output (.idx): ${_outputLynPath == null ? '(not selected)' : '${_outputLynPath!}.idx'}',
        ),
        Text('Excludes: ${_excludePatterns.join(', ')}'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          height: 168,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            border: Border.all(
              color: indexingState.error != null
                  ? Colors.red
                  : const Color(0xFF444444),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            reverse: true,
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: displayLines
                    .map(
                      (line) => Text(
                        line.isEmpty ? ' ' : line,
                        style: TextStyle(
                          color: indexingState.error != null
                              ? const Color(0xFFFF8A80)
                              : const Color(0xFF00FF66),
                          fontSize: 12,
                          fontFamily: 'Courier New',
                          height: 1.4,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onStepContinue() {
    if (_currentStep == 0 && _selectedPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a source folder first.')),
      );
      return;
    }

    if (_currentStep == 1) {
      if (_nameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please provide an index name.')),
        );
        return;
      }
      if (_outputLynPath == null || _outputLynPath!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please choose an output .lyn file path.'),
          ),
        );
        return;
      }
    }

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

  Future<void> _pickOutputFile() async {
    final suggestedName = _nameController.text.trim().isEmpty
        ? 'index.lyn'
        : '${_nameController.text.trim()}.lyn';

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Choose where to save the index archive',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['lyn'],
    );

    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        _outputLynPath = _normalizeLynPath(result.trim());
      });
    }
  }

  String _normalizeLynPath(String inputPath) {
    if (inputPath.toLowerCase().endsWith('.lyn')) {
      return inputPath;
    }
    return '$inputPath.lyn';
  }

  Future<void> _createIndex() async {
    if (_selectedPath == null || _nameController.text.trim().isEmpty) return;
    if (_outputLynPath == null || _outputLynPath!.trim().isEmpty) return;

    final lynPath = _normalizeLynPath(_outputLynPath!.trim());

    final index = IndexModel(
      name: _nameController.text.trim(),
      sourcePath: _selectedPath!,
      lynPath: lynPath,
      indexPath: '$lynPath.idx',
      excludePatterns: _excludePatterns,
      createdAt: DateTime.now(),
    );

    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create index: $e')));
      }
    }
  }
}
