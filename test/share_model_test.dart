import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/models/models.dart';

/// `listInbox`/`listSent` in `../web/services/share.service.ts` select
/// `reaction_count` as a bare `COUNT(*)`, and node-postgres serialises
/// `bigint` as a string — so the field arrives as `"2"`, not `2`, however the
/// TypeScript type describes it. Parsing it with a plain cast threw inside
/// `Share.fromJson` and took the whole Sent/Inbox list down with a generic
/// "Something went wrong".
void main() {
  Map<String, dynamic> sentRow({dynamic reactionCount}) => {
        'id': 'share-1',
        'sender_id': 'user-1',
        'provider': 'filmhub',
        'show_id': '4242',
        'message': 'watch this',
        'created_at': '2026-08-14T10:00:00.000Z',
        'recipients': [
          {'id': 'user-2', 'display_name': 'Ada', 'read_at': null},
        ],
        'reaction_count': reactionCount,
      };

  test('reaction_count parses whether it arrives as a string or a number', () {
    expect(Share.fromJson(sentRow(reactionCount: '2')).reactionCount, 2);
    expect(Share.fromJson(sentRow(reactionCount: 2)).reactionCount, 2);
  });

  test('a missing or unparseable reaction_count falls back to the reactions',
      () {
    expect(Share.fromJson(sentRow(reactionCount: null)).reactionCount, 0);
    expect(Share.fromJson(sentRow(reactionCount: 'nope')).reactionCount, 0);
  });

  test('clip bounds parse from strings too', () {
    final share = Share.fromJson({
      ...sentRow(reactionCount: '0'),
      'clip_start_seconds': '90',
      'clip_end_seconds': '150',
    });
    expect(share.clipStartSeconds, 90);
    expect(share.clipEndSeconds, 150);
    expect(share.isClip, isTrue);
  });

  test('a sent row without a sender object still parses', () {
    final share = Share.fromJson(sentRow(reactionCount: '0'));
    expect(share.id, 'share-1');
    expect(share.recipients.single.label, 'Ada');
    expect(share.sender.id, isEmpty);
  });
}
