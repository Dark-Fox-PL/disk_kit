/// Measured file-copy events. No estimate or in-flight cancellation is implied.
class FileCopyProgress {
  const FileCopyProgress(
      {required this.path, required this.bytes, required this.completed});
  final String path;
  final int bytes;
  final bool completed;
  factory FileCopyProgress.fromMap(Map<Object?, Object?> map) =>
      FileCopyProgress(
        path: map['path'] as String,
        bytes: map['bytes'] as int,
        completed: map['completed'] as bool,
      );
}

typedef FileCopyProgressCallback = void Function(FileCopyProgress progress);
