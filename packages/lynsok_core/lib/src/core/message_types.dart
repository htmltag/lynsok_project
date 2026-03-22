import 'dart:isolate';

/// Message types for communication between main isolate and worker isolates.
/// Each message is represented as a Map with a 'type' field to identify the message type.
/// - WorkTask: Sent from main isolate to worker isolate to assign a new task.
/// - ResultTask: Sent from worker isolate to main isolate to report results of a completed task.
/// The WorkTask contains an ID and the data to be processed, while the ResultTask contains the ID, pattern counts, execution time, and optionally extracted data.
/// This structure allows for clear and efficient communication between isolates, enabling the main isolate to manage multiple worker isolates and aggregate results effectively.
class WorkTask {
  final int id;
  final TransferableTypedData data;

  WorkTask(this.id, this.data);

  Map<String, dynamic> toMessage() => {'type': 'work', 'id': id, 'data': data};

  static WorkTask fromMessage(Map m) =>
      WorkTask(m['id'] as int, m['data'] as TransferableTypedData);
}


/// The ResultTask class represents the results of a completed task performed by a worker isolate. It includes the task ID, a map of pattern counts, the execution time in milliseconds, and optionally any extracted data. The toMessage method converts the ResultTask instance into a Map format suitable for sending back to the main isolate, while the fromMessage static method allows for reconstructing a ResultTask instance from a received message.
/// This design enables efficient communication of results from worker isolates to the main isolate, allowing for aggregation and further processing of the results as needed.
/// The use of TransferableTypedData for the extracted field allows for efficient transfer of large data without copying, which is particularly beneficial when dealing with large datasets or results that need to be sent back to the main isolate.
/// Overall, the ResultTask class serves as a structured way to encapsulate the results of tasks performed by worker isolates and facilitates seamless communication between isolates in a Dart application.
/// Example usage:
/// ```dart
/// // In worker isolate:
/// final result = ResultTask(taskId, patternCounts, executionTime, extractedData);
/// final message = result.toMessage();
/// // In main isolate:
/// final result = ResultTask.fromMessage(message);
/// ```
class ResultTask {
  final int id;
  final Map<String, int> patternCounts;
  final double executionMs;
  final TransferableTypedData? extracted;

  ResultTask(this.id, this.patternCounts, this.executionMs, [this.extracted]);

  Map<String, dynamic> toMessage() {
    final Map<String, dynamic> msg = {
      'type': 'result',
      'id': id,
      'patternCounts': patternCounts,
      'executionMs': executionMs,
    };
    if (extracted != null) {
      msg['extracted'] = extracted;
    }
    return msg;
  }

  static ResultTask fromMessage(Map m) => ResultTask(
    m['id'] as int,
    Map<String, int>.from(m['patternCounts'] as Map),
    (m['executionMs'] as num).toDouble(),
    m.containsKey('extracted') ? m['extracted'] as TransferableTypedData : null,
  );
}
