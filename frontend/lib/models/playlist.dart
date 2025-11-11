class PlaylistItem {
  final int segmentId;
  final Uri url;
  final int? durationMs;

  PlaylistItem({required this.segmentId, required this.url, this.durationMs});
}

class Playlist {
  final String documentId;
  final String voiceId;
  final List<PlaylistItem> items;
  final int startSegmentId;
  final int startIntraMs;

  Playlist({
    required this.documentId,
    required this.voiceId,
    required this.items,
    required this.startSegmentId,
    required this.startIntraMs,
  });

  bool get isEmpty => items.isEmpty;
}
