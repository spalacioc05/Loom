class PlayProgress {
  final String documentId;
  final String voiceId;
  final int segmentId;
  final int intraMs;
  final int? globalOffsetChar; // opcional para futuro

  PlayProgress({
    required this.documentId,
    required this.voiceId,
    required this.segmentId,
    required this.intraMs,
    this.globalOffsetChar,
  });

  Map<String, dynamic> toJson() => {
        'document_id': documentId,
        'voice_id': voiceId,
        'segment_id': segmentId,
        'intra_ms': intraMs,
        'global_offset_char': globalOffsetChar,
      };

  factory PlayProgress.fromJson(Map<String, dynamic> json) => PlayProgress(
        documentId: json['document_id'] as String,
        voiceId: json['voice_id'] as String,
        segmentId: (json['segment_id'] as num).toInt(),
        intraMs: (json['intra_ms'] as num).toInt(),
        globalOffsetChar: (json['global_offset_char'] as num?)?.toInt(),
      );
}
