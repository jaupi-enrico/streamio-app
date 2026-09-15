/// One skippable window in a title's timeline. Mirrors
/// `NormalizedSegmentTimestamp` from the `theintrodb` npm client the backend
/// uses (`../../../../web/services/intro-db.service.ts`) — `startMs` is
/// always a number (a `null` start became `0` server-side), `endMs` stays
/// `null` to mean "runs to the end of the media".
class IntroSegment {
  const IntroSegment({required this.startMs, this.endMs});

  factory IntroSegment.fromJson(Map<String, dynamic> json) => IntroSegment(
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt(),
      );

  final int startMs;
  final int? endMs;
}

/// Segment kind, in the priority order the "Skip …" button checks them —
/// mirrors `SKIP_SEGMENT_LABELS`/`findActiveSkipSegment()` in
/// `../../../../web/public/scripts/watch.js`.
enum SkipSegmentType { intro, recap, credits, preview }

/// `GET /api/intro-segments` response — mirrors `IntroDbMedia` server-side
/// (itself the `theintrodb` client's `MediaRecord`).
class IntroDbMedia {
  const IntroDbMedia({
    this.intro = const [],
    this.recap = const [],
    this.credits = const [],
    this.preview = const [],
  });

  factory IntroDbMedia.fromJson(Map<String, dynamic> json) {
    List<IntroSegment> list(String key) => (json[key] as List? ?? const [])
        .whereType<Map>()
        .map((e) => IntroSegment.fromJson(e.cast<String, dynamic>()))
        .toList();
    return IntroDbMedia(
      intro: list('intro'),
      recap: list('recap'),
      credits: list('credits'),
      preview: list('preview'),
    );
  }

  final List<IntroSegment> intro;
  final List<IntroSegment> recap;
  final List<IntroSegment> credits;
  final List<IntroSegment> preview;

  List<IntroSegment> forType(SkipSegmentType type) => switch (type) {
        SkipSegmentType.intro => intro,
        SkipSegmentType.recap => recap,
        SkipSegmentType.credits => credits,
        SkipSegmentType.preview => preview,
      };
}
