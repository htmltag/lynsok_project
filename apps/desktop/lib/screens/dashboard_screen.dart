import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop/models/index_model.dart';
import 'package:desktop/providers/index_provider.dart';
import 'package:desktop/widgets/index_card.dart';
import 'package:desktop/screens/index_creation_wizard.dart';
import 'package:desktop/screens/index_detail_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexState = ref.watch(indexProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LynSøk Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(indexProvider.notifier).refreshIndexes(),
            tooltip: 'Refresh indexes',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Open settings screen
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: indexState.indexes.isEmpty
          ? _buildEmptyState(context)
          : _buildIndexGrid(context, indexState.indexes),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const IndexCreationWizard()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('New Index'),
        tooltip: 'Create new search index',
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 24),
          Text(
            'No indexes yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first search index to get started',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IndexCreationWizard()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Create Index'),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexGrid(BuildContext context, List<IndexModel> indexes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive grid: 1 column on small screens, 2-3 on larger
        final crossAxisCount = constraints.maxWidth > 1200
            ? 3
            : constraints.maxWidth > 800
                ? 2
                : 1;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.2, // Slightly taller than wide
          ),
          itemCount: indexes.length,
          itemBuilder: (context, index) {
            return IndexCard(
              indexModel: indexes[index],
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => IndexDetailScreen(index: indexes[index]),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}