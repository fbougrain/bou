enum MediaType { photo, document, video }

class MediaItem {
  final String id;
  final String name;
  final MediaType type;
  final DateTime date;
  final String uploader;
  final String? taskId;
  final String? thumbnailUrl;

  const MediaItem({
    required this.id,
    required this.name,
    required this.type,
    required this.date,
    required this.uploader,
    this.taskId,
    this.thumbnailUrl,
  });
}
