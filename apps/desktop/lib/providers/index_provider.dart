import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:desktop/models/index_model.dart';
import 'package:desktop/services/database_service.dart';

final indexProvider = StateNotifierProvider<IndexNotifier, IndexState>((ref) {
  return IndexNotifier();
});

class IndexState {
  final bool isInitialized;
  final bool isLoading;
  final List<IndexModel> indexes;
  final String? error;

  const IndexState({
    this.isInitialized = false,
    this.isLoading = false,
    this.indexes = const [],
    this.error,
  });

  IndexState copyWith({
    bool? isInitialized,
    bool? isLoading,
    List<IndexModel>? indexes,
    String? error,
  }) {
    return IndexState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      indexes: indexes ?? this.indexes,
      error: error,
    );
  }
}

class IndexNotifier extends StateNotifier<IndexState> {
  Database? _database;

  IndexNotifier() : super(const IndexState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      state = state.copyWith(isLoading: true);

      _database = await DatabaseService.getInstance();

      final indexes = await _getAllIndexes();
      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        indexes: indexes,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<List<IndexModel>> _getAllIndexes() async {
    if (_database == null) return [];

    final maps = await _database!.query('indexes');
    return maps.map((map) => IndexModel.fromMap(map)).toList();
  }

  Future<void> addIndex(IndexModel index) async {
    if (_database == null) return;

    try {
      final id = await _database!.insert('indexes', index.toMap());
      final newIndex = index.copyWith(id: id);

      final indexes = [...state.indexes, newIndex];
      state = state.copyWith(indexes: indexes, error: null);
    } on DatabaseException catch (e) {
      final msg =
          'Failed to save index metadata. If this is an existing install, restart the app to run DB migration. Details: ${e.toString()}';
      state = state.copyWith(error: msg);
      throw StateError(msg);
    }
  }

  Future<void> updateIndex(IndexModel index) async {
    if (_database == null || index.id == null) return;

    try {
      await _database!.update(
        'indexes',
        index.toMap(),
        where: 'id = ?',
        whereArgs: [index.id],
      );

      final indexes = state.indexes
          .map((i) => i.id == index.id ? index : i)
          .toList();
      state = state.copyWith(indexes: indexes, error: null);
    } on DatabaseException catch (e) {
      final msg = 'Failed to update index metadata: ${e.toString()}';
      state = state.copyWith(error: msg);
      throw StateError(msg);
    }
  }

  Future<void> removeIndex(int id) async {
    if (_database == null) return;

    await _database!.delete('indexes', where: 'id = ?', whereArgs: [id]);

    final indexes = state.indexes.where((i) => i.id != id).toList();
    state = state.copyWith(indexes: indexes);
  }

  Future<void> refreshIndexes() async {
    if (_database == null) return;

    final indexes = await _getAllIndexes();
    state = state.copyWith(indexes: indexes);
  }

  @override
  void dispose() {
    DatabaseService.close();
    super.dispose();
  }
}
