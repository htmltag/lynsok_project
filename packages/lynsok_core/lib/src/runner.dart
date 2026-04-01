import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'core/isolate_pool.dart';
import 'connectors/file_connector.dart';
import 'connectors/directory_connector.dart';
import 'utils/directory_scanner.dart';
import 'core/file_types.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';
import 'utils/file_sniffer.dart';
import 'utils/lyn_format.dart';
import 'utils/lyn_index.dart';

// private helper to track ongoing archive state
class _RecordState {
  final String path;
  int bodyLengthOffset;
  int totalBodyBytes = 0;
  bool headerPatched = false;
  _RecordState(this.path, this.bodyLengthOffset);
}

class LynSokRunner {
  final int isolates;
  final Map<String, Uint8List> patterns;
  final bool caseInsensitive;
  final bool jsonMode;
  final bool verbose;

  /// When non-null we operate in compaction mode and write a single Lyn file.
  final String? compactOutput;
  final bool buildIndex;
  final String? indexOutput;
  final void Function(String line)? onLog;

  LynSokRunner({
    required this.isolates,
    required this.patterns,
    required this.caseInsensitive,
    this.jsonMode = false,
    this.compactOutput,
    this.buildIndex = false,
    this.indexOutput,
    this.verbose = false,
    this.onLog,
  });

  void _log(String message) {
    if (!verbose) {
      return;
    }
    stdout.writeln(message);
    onLog?.call(message);
  }

  Future<int> run(String path) async {
    final pathType = DirectoryScanner.getPathType(path);
    final bool compactMode = compactOutput != null;
    String? outNorm;
    if (compactMode) {
      _log('Compact mode output path: $compactOutput');
      outNorm = p.normalize(File(compactOutput!).absolute.path);
    }

    RandomAccessFile? archiveRaf;
    final Map<String, _RecordState> activeRecords = {};

    // optional index builder
    final bool shouldBuildIndex = compactMode && buildIndex;
    final LynIndex? index = shouldBuildIndex ? LynIndex() : null;

    // lock used to serialize all RandomAccessFile operations
    final rafLock = Lock();

    // non-nullable helper used when in compaction mode
    late RandomAccessFile raf;
    if (compactMode) {
      // prepare the output file: open for write, write magic/version
      final outFile = File(compactOutput!);
      archiveRaf = await outFile.open(mode: FileMode.write);
      raf = archiveRaf;
      // write global header under lock
      await rafLock.synchronized(() async {
        await raf.writeFrom(lynMagic);
        await raf.writeFrom(lynVersion);
      });
    }
    Stream<Map<String, dynamic>> chunkStream;

    if (pathType == PathType.directory) {
      chunkStream = DirectoryConnector(path).streamChunks();
    } else if (pathType == PathType.file) {
      chunkStream = FileConnector(path).streamChunks();
    } else {
      stderr.writeln('Error: Path not found: $path');
      return 1;
    }

    final pool = IsolatePool(isolates);
    await pool.start();

    FileType fileType = FileType.unknown;

    final active = <Future>[];
    final totalMatches = <String, int>{};

    await for (final chunk in chunkStream) {
      final bool isFirstChunk = chunk['isFirst'] == true;
      final bool isLastChunk = chunk['isLast'] == true;
      final String? chunkPath = chunk['path'] as String?;

      // avoid reading our own output file if it's inside the input tree
      if (compactMode && outNorm != null && chunkPath != null) {
        final cpNorm = p.normalize(File(chunkPath).absolute.path);
        _log('skip check: cpNorm=$cpNorm ; outNorm=$outNorm');
        if (cpNorm == outNorm) {
          _log('skipping archive file');
          continue;
        }
      }

      if (isFirstChunk) {
        final ttd = chunk['data'] as TransferableTypedData;
        final data = ttd.materialize().asUint8List();
        fileType = FileSniffer.detect(data);
        chunk['data'] = TransferableTypedData.fromList([data]);
        _log('Detected file type: $fileType for path $chunkPath');

        if (compactMode && chunkPath != null) {
          // start a new record for this file; do it under lock
          await rafLock.synchronized(() async {
            final bodyOffset = await writeRecordHeader(raf, chunkPath);
            activeRecords[chunkPath] = _RecordState(chunkPath, bodyOffset);
            _log('Started archive record for $chunkPath at offset $bodyOffset');
          });
        }
      }

      final workPayload = <String, dynamic>{
        'data': chunk['data'],
        'isFirst': isFirstChunk,
        'baseSize': chunk['baseSize'],
        'patterns': patterns,
        'caseInsensitive': caseInsensitive,
        'isJsonMode': jsonMode,
        'fileType': fileType.index,
      };
      if (compactMode) {
        workPayload['mode'] = 'compact';
      }

      final future = pool
          .submit(workPayload)
          .then((r) async {
            if (compactMode) {
              // r.extracted must contain bytes
              final extractedData =
                  r.extracted?.materialize().asUint8List() ?? Uint8List(0);
              if (chunkPath != null) {
                final state = activeRecords[chunkPath]!;
                // perform all RAF operations under lock to avoid conflicts
                await rafLock.synchronized(() async {
                  _log(
                    '  writing ${extractedData.length} bytes for $chunkPath',
                  );
                  await raf.writeFrom(extractedData);
                  state.totalBodyBytes += extractedData.length;
                  if (isLastChunk && !state.headerPatched) {
                    _log(
                      '  patching length ${state.totalBodyBytes} for $chunkPath',
                    );
                    final curPos = await raf.position();
                    await patchBodyLength(
                      raf,
                      state.bodyLengthOffset,
                      state.totalBodyBytes,
                    );
                    // restore position so we are at end before writing ETX
                    await raf.setPosition(curPos);
                    state.headerPatched = true;
                    _log('  writing ETX for $chunkPath');
                    await raf.writeByte(etx);
                  }
                });
              }
            } else {
              _log('Chunk ${r.id} => ${r.patternCounts}');
              r.patternCounts.forEach((label, count) {
                totalMatches[label] = (totalMatches[label] ?? 0) + count;
              });
            }
          })
          .catchError((e) {
            stderr.writeln('Error processing chunk: $e');
          });

      active.add(future);

      if (active.length >= isolates * 2) {
        await Future.wait(active, eagerError: false);
        active.clear();
      }
    }

    await Future.wait(active);
    await pool.stop();
    if (compactMode) {
      _log('Active records tracked: ${activeRecords.keys.toList()}');
    }

    if (compactMode) {
      // patch any unfinished records after previous writes
      await rafLock.synchronized(() async {
        for (var state in activeRecords.values) {
          if (!state.headerPatched) {
            final curPos = await raf.position();
            await patchBodyLength(
              raf,
              state.bodyLengthOffset,
              state.totalBodyBytes,
            );
            await raf.setPosition(curPos);
            state.headerPatched = true;
            await raf.writeByte(etx);
          }
        }
      });

      if (shouldBuildIndex && index != null) {
        final idxPath = indexOutput ?? '$compactOutput.idx';
        final idxFile = File(idxPath);

        // Read each record body from the archive and add it to the index.
        for (var state in activeRecords.values) {
          final bodyOffset =
              state.bodyLengthOffset + 8; // body starts after length field
          final bodyLength = state.totalBodyBytes;
          await rafLock.synchronized(() async {
            await raf.setPosition(bodyOffset);
            final bodyBytes = await raf.read(bodyLength);
            index.addDocument(
              path: state.path,
              bodyOffset: bodyOffset,
              bodyLength: bodyLength,
              bodyBytes: bodyBytes,
            );
          });
        }

        await index.saveTo(idxFile);
        _log('Wrote index to $idxPath');
      }

      if (verbose) {
        _log('Active records tracked: ${activeRecords.keys.toList()}');
      }
    }

    return totalMatches.values.fold<int>(0, (sum, count) => sum + count);
  }
}
