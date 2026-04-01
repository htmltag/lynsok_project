import 'package:desktop/models/index_model.dart';
import 'package:desktop/providers/index_provider.dart';
import 'package:desktop/providers/theme_mode_provider.dart';
import 'package:desktop/screens/index_creation_wizard.dart';
import 'package:desktop/screens/index_detail_screen.dart';
import 'package:desktop/widgets/index_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _SidebarSection { dashboard, indexManager, aiSettings }

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  _SidebarSection _selectedSection = _SidebarSection.dashboard;

  @override
  Widget build(BuildContext context) {
    final indexState = ref.watch(indexProvider);
    final themeMode = ref.watch(themeModeProvider);

    final title = switch (_selectedSection) {
      _SidebarSection.dashboard => 'Dashboard',
      _SidebarSection.indexManager => 'Index Manager',
      _SidebarSection.aiSettings => 'AI Settings',
    };

    final subtitle = switch (_selectedSection) {
      _SidebarSection.dashboard =>
        'Manage your local search indices and archives',
      _SidebarSection.indexManager =>
        'Create, open, and synchronize index archives',
      _SidebarSection.aiSettings =>
        'Configure local LLM providers and assistant prompts',
    };

    return Scaffold(
      body: Row(
        children: [
          _DesktopSidebar(
            selectedSection: _selectedSection,
            hasIndexes: indexState.indexes.isNotEmpty,
            themeMode: themeMode,
            onToggleTheme: () {
              final nextMode = themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              ref.read(themeModeProvider.notifier).state = nextMode;
            },
            onSectionSelected: (section) {
              setState(() => _selectedSection = section);
            },
          ),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 28, 32, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton.outlined(
                        onPressed: () =>
                            ref.read(indexProvider.notifier).refreshIndexes(),
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh indexes',
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const IndexCreationWizard(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Create New Index'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: switch (_selectedSection) {
                    _SidebarSection.dashboard || _SidebarSection.indexManager =>
                      indexState.indexes.isEmpty
                          ? _buildEmptyState(context)
                          : _buildIndexGrid(context, indexState.indexes),
                    _SidebarSection.aiSettings => _buildAiSettingsPlaceholder(
                      context,
                    ),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.folder_open_rounded,
                    size: 34,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Create New Index',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Add a new .lyn archive to start local document search.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const IndexCreationWizard(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Create Index'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIndexGrid(BuildContext context, List<IndexModel> indexes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 1600
              ? 4
              : constraints.maxWidth > 1200
              ? 3
              : constraints.maxWidth > 840
              ? 2
              : 1;

          return GridView.builder(
            padding: const EdgeInsets.only(bottom: 4),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
              childAspectRatio: 0.9,
            ),
            itemCount: indexes.length + 1,
            itemBuilder: (context, index) {
              if (index == indexes.length) {
                return _AddIndexCard(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const IndexCreationWizard(),
                      ),
                    );
                  },
                );
              }

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
      ),
    );
  }

  Widget _buildAiSettingsPlaceholder(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 34,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'AI Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Provider configuration can be managed from each index detail page under Search & RAG.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  final _SidebarSection selectedSection;
  final bool hasIndexes;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final ValueChanged<_SidebarSection> onSectionSelected;

  const _DesktopSidebar({
    required this.selectedSection,
    required this.hasIndexes,
    required this.themeMode,
    required this.onToggleTheme,
    required this.onSectionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final sections = [
      (_SidebarSection.dashboard, 'Dashboard', Icons.dashboard_outlined),
      (_SidebarSection.indexManager, 'Index Manager', Icons.storage_outlined),
      (_SidebarSection.aiSettings, 'AI Settings', Icons.auto_awesome_outlined),
    ];

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.headlineSmall,
                    children: [
                      TextSpan(
                        text: 'Lyn',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const TextSpan(text: 'Sok'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'v0.1.0',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).colorScheme.outline),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final (section, label, icon) in sections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _SidebarButton(
                      selected: selectedSection == section,
                      label: label,
                      icon: icon,
                      onTap: () => onSectionSelected(section),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).colorScheme.outline),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: hasIndexes
                              ? Colors.green
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasIndexes
                              ? 'Indexes available'
                              : 'No indexes loaded',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _ThemeToggleButton(
                    isDarkMode: themeMode == ThemeMode.dark,
                    onPressed: onToggleTheme,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatefulWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SidebarButton({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _isHovered;

    return Material(
      color: active
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: _isHovered ? 1.015 : 1,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 140),
              padding: EdgeInsets.fromLTRB(_isHovered ? 14 : 12, 10, 12, 10),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 20,
                    color: widget.selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: widget.selected
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggleButton extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onPressed;

  const _ThemeToggleButton({required this.isDarkMode, required this.onPressed});

  @override
  State<_ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends State<_ThemeToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.isDarkMode
          ? 'Switch to light theme'
          : 'Switch to dark theme',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: _isHovered ? 0.8 : 0.45),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _isHovered
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: widget.onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.isDarkMode
                      ? Icons.dark_mode_outlined
                      : Icons.wb_sunny_outlined,
                  size: 18,
                  color: _isHovered
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isDarkMode ? 'Dark' : 'Light',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _isHovered
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddIndexCard extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddIndexCard({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return _HoverLift(
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    Icons.create_new_folder_outlined,
                    size: 30,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Create New Index',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Add a new .lyn archive',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverLift extends StatefulWidget {
  final Widget child;

  const _HoverLift({required this.child});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: _isHovered ? 1.01 : 1,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 150),
          offset: _isHovered ? const Offset(0, -0.01) : Offset.zero,
          child: widget.child,
        ),
      ),
    );
  }
}
