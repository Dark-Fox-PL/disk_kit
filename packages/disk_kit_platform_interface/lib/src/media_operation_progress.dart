/// The current stage of writing an image or creating installation media.
enum MediaOperationStage {
  /// Checking the source, target, and any required tools before erasure.
  preparing,

  /// Asking macOS to unmount all target volumes without forcing them.
  unmounting,

  /// Waiting for the system administrator authorization dialog.
  authorizing,

  /// Replacing the target's partition table and filesystem.
  formatting,

  /// Writing image bytes or copying installation files.
  writing,

  /// Splitting an oversized Windows installation WIM into SWM files.
  splitting,

  /// Flushing writes or finishing the installation media layout.
  syncing,

  /// Reading the destination back and comparing it with the source.
  verifying,

  /// The native operation finished successfully.
  completed,
}

/// Progress for one destructive media operation.
///
/// Byte counters apply to [stage], not the entire workflow. Stages without a
/// measurable total have null counters; applications should show an
/// indeterminate indicator. Successful writing does not guarantee compatibility
/// with a particular computer's firmware or processor architecture.
class MediaOperationProgress {
  /// Creates an immutable progress update.
  const MediaOperationProgress({
    required this.diskId,
    required this.stage,
    this.bytesCompleted,
    this.totalBytes,
  });

  /// The whole-disk identifier selected for this operation.
  final String diskId;

  /// The current native stage.
  final MediaOperationStage stage;

  /// Bytes processed within this stage, when reported by the native tool.
  final int? bytesCompleted;

  /// Expected bytes within this stage, when known.
  final int? totalBytes;

  /// Stage completion between zero and one, or null for an unknown total.
  double? get fraction => bytesCompleted != null && (totalBytes ?? 0) > 0
      ? (bytesCompleted! / totalBytes!).clamp(0.0, 1.0)
      : null;

  /// Decodes the shared native-channel progress representation.
  factory MediaOperationProgress.fromMap(Map<Object?, Object?> map) =>
      MediaOperationProgress(
        diskId: map['diskId'] as String,
        stage: MediaOperationStage.values.byName(map['stage'] as String),
        bytesCompleted: map['bytesCompleted'] as int?,
        totalBytes: map['totalBytes'] as int?,
      );
}

/// Receives progress updates until a media operation's future completes.
typedef MediaProgressCallback = void Function(MediaOperationProgress progress);
