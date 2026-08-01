/// A server-scraped video source reference. Mirrors the `{id, name, src}`
/// shape `GET /api/episodes/:id/servers` returns (core/models/Video.ts's
/// `Server` class on the backend), and the object that must be echoed back
/// verbatim in the body of `POST /api/episodes/:id/video`.
class VideoServer {
  const VideoServer({required this.id, required this.name, required this.src});

  factory VideoServer.fromJson(Map<String, dynamic> json) {
    return VideoServer(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? json['server'] ?? '').toString(),
      src: json['src']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final String src;

  /// The backend re-resolves from this exact object, so it goes back on the
  /// wire unchanged rather than as a re-derived subset.
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'src': src};
}
