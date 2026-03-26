import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:lynsok_core/src/workers/lynsok_engine.dart';
import 'message_types.dart';

/// Manages a pool of isolates to process log files concurrently.
/// Each isolate runs the log processor entry point and communicates via SendPort/ReceivePort.
/// Tasks are submitted to the pool, which distributes them to available workers and collects results asynchronously.
/// The pool handles worker initialization, task queuing, and result collection, allowing for efficient parallel processing of log files.
/// Example usage:
/// ```dart
/// final pool = IsolatePool(4);
/// await pool.start();
/// final result = await pool.submit({'filePath': 'logs/app.log', 'patterns': ['ERROR', 'WARN']});
/// print(result.patternCounts);
/// await pool.stop();
/// ```
class IsolatePool {
  final int size;
  final _workerPorts = <int, SendPort>{};
  final _isolates = <Isolate>[];
  final _pending = <Map<String, dynamic>>[];
  final _completers = <int, Completer<ResultTask>>{};
  final _receivePort = ReceivePort();
  int _nextWorker = 0;
  int _taskId = 0;

  IsolatePool(this.size);

  Future<void> start() async {
    _receivePort.listen(_handleMessage);
    for (var i = 0; i < size; i++) {
      final isolate = await Isolate.spawn(
        logProcessorEntryPoint,
        _receivePort.sendPort,
      );
      _isolates.add(isolate);
    }
  }

  void _handleMessage(dynamic message) {
    if (message is Map) {
      final type = message['type'] as String?;
      if (type == 'workerReady') {
        final port = message['port'] as SendPort;
        final id = _workerPorts.length;
        _workerPorts[id] = port;
        // flush pending work
        while (_pending.isNotEmpty && _workerPorts.isNotEmpty) {
          final work = _pending.removeAt(0);
          port.send(work);
        }
        return;
      }

      if (type == 'result') {
        final id = message['id'] as int;
        final patternCounts = Map<String, int>.from(message['counts'] as Map);
        final executionMs = (message['executionMs'] as num?)?.toDouble() ?? 0.0;
        final TransferableTypedData? extracted =
            message.containsKey('extracted')
            ? message['extracted'] as TransferableTypedData
            : null;
        final completer = _completers.remove(id);
        if (completer != null) {
          completer.complete(
            ResultTask(id, patternCounts, executionMs, extracted),
          );
        }
        return;
      }

      if (type == 'error') {
        final id = message['id'] as int?;
        final error = message['error'] as String?;
        stderr.writeln('Worker error for task $id: $error');
        if (id != null) {
          final completer = _completers.remove(id);
          if (completer != null) {
            completer.completeError(Exception('Worker error: $error'));
          }
        }
        return;
      }
    }
  }

  Future<ResultTask> submit(Map<String, dynamic> payload) {
    final id = _taskId++;
    final completer = Completer<ResultTask>();
    _completers[id] = completer;

    final work = <String, dynamic>{'type': 'work', 'id': id};
    work.addAll(payload);

    if (_workerPorts.isEmpty) {
      _pending.add(work);
    } else {
      final workerId = _nextWorker % _workerPorts.length;
      _nextWorker++;
      final port = _workerPorts[workerId]!;
      port.send(work);
    }

    return completer.future;
  }

  Future<void> stop() async {
    for (final iso in _isolates) {
      iso.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _workerPorts.clear();
    _receivePort.close();
  }
}
