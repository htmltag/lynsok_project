class IndexModel {
  static const Object _sentinel = Object();

  int? id;
  String name;
  String sourcePath;
  String lynPath;
  String indexPath;
  int fileCount;
  int totalSize;
  DateTime createdAt;
  DateTime? lastIndexedAt;
  bool serverActive;
  List<String> excludePatterns;
  int? httpServerPid;
  int? mcpServerPid;
  int? httpPort;
  int? mcpPort;

  IndexModel({
    this.id,
    required this.name,
    required this.sourcePath,
    required this.lynPath,
    required this.indexPath,
    this.fileCount = 0,
    this.totalSize = 0,
    DateTime? createdAt,
    this.lastIndexedAt,
    this.serverActive = false,
    this.excludePatterns = const [],
    this.httpServerPid,
    this.mcpServerPid,
    this.httpPort,
    this.mcpPort,
  }) : createdAt = createdAt ?? DateTime.now();

  // Convert to Map for database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'sourcePath': sourcePath,
      'lynPath': lynPath,
      'indexPath': indexPath,
      'fileCount': fileCount,
      'totalSize': totalSize,
      'createdAt': createdAt.toIso8601String(),
      'lastIndexedAt': lastIndexedAt?.toIso8601String(),
      'serverActive': serverActive ? 1 : 0,
      'excludePatterns': excludePatterns.join(';'),
      'httpServerPid': httpServerPid,
      'mcpServerPid': mcpServerPid,
      'httpPort': httpPort,
      'mcpPort': mcpPort,
    };
  }

  // Create from Map
  factory IndexModel.fromMap(Map<String, dynamic> map) {
    return IndexModel(
      id: map['id'],
      name: map['name'],
      sourcePath: map['sourcePath'],
      lynPath: map['lynPath'],
      indexPath: map['indexPath'],
      fileCount: map['fileCount'] ?? 0,
      totalSize: map['totalSize'] ?? 0,
      createdAt: DateTime.parse(map['createdAt']),
      lastIndexedAt: map['lastIndexedAt'] != null
          ? DateTime.parse(map['lastIndexedAt'])
          : null,
      serverActive: map['serverActive'] == 1,
      excludePatterns: map['excludePatterns']?.split(';') ?? [],
      httpServerPid: map['httpServerPid'] as int?,
      mcpServerPid: map['mcpServerPid'] as int?,
      httpPort: map['httpPort'] as int?,
      mcpPort: map['mcpPort'] as int?,
    );
  }

  IndexModel copyWith({
    int? id,
    String? name,
    String? sourcePath,
    String? lynPath,
    String? indexPath,
    int? fileCount,
    int? totalSize,
    DateTime? createdAt,
    DateTime? lastIndexedAt,
    bool? serverActive,
    List<String>? excludePatterns,
    int? httpServerPid,
    int? mcpServerPid,
    Object? httpPort = _sentinel,
    Object? mcpPort = _sentinel,
  }) {
    return IndexModel(
      id: id ?? this.id,
      name: name ?? this.name,
      sourcePath: sourcePath ?? this.sourcePath,
      lynPath: lynPath ?? this.lynPath,
      indexPath: indexPath ?? this.indexPath,
      fileCount: fileCount ?? this.fileCount,
      totalSize: totalSize ?? this.totalSize,
      createdAt: createdAt ?? this.createdAt,
      lastIndexedAt: lastIndexedAt ?? this.lastIndexedAt,
      serverActive: serverActive ?? this.serverActive,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      httpServerPid: httpServerPid ?? this.httpServerPid,
      mcpServerPid: mcpServerPid ?? this.mcpServerPid,
      httpPort: identical(httpPort, _sentinel)
          ? this.httpPort
          : httpPort as int?,
      mcpPort: identical(mcpPort, _sentinel) ? this.mcpPort : mcpPort as int?,
    );
  }

  // Computed properties
  String get displayName => name.isNotEmpty ? name : sourcePath.split('/').last;

  String get formattedSize {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = totalSize.toDouble();
    var unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  String get formattedFileCount {
    if (fileCount < 1000) return fileCount.toString();
    if (fileCount < 1000000) return '${(fileCount / 1000).toStringAsFixed(1)}K';
    return '${(fileCount / 1000000).toStringAsFixed(1)}M';
  }

  String get formattedLastModified {
    if (lastIndexedAt == null) return 'Never';
    final now = DateTime.now();
    final difference = now.difference(lastIndexedAt!);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  bool get isServerRunning => serverActive;

  bool get hasErrors => false; // TODO: Implement error checking
}
