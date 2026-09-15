import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/models/models.dart';

/// `GET /api/account/stats` returns Postgres-derived snake_case rows, and
/// `pg` hands bigints back as strings — the trap `Share.reactionCount` already
/// hit — so every number has to survive arriving as either.
void main() {
  test('parses the full payload', () {
    final stats = AccountStats.fromJson({
      'stats': {
        'total_watch_seconds': 512345,
        'episodes_completed': 210,
        'movies_completed': 34,
        'episodes_in_progress': 6,
        'titles_started': 88,
        'shows_completed': 12,
        'watchlist_count': 41,
        'favorites_count': 19,
        'ratings_count': 25,
        'average_rating': 7.6,
        'providers_used': 3,
        'top_provider': 'filmhub',
        'active_days': 140,
        'current_streak_days': 5,
        'longest_streak_days': 31,
        'followers_count': 4,
        'following_count': 7,
        'shares_sent': 12,
        'shares_received': 9,
        'reactions_received': 30,
        'member_since': '2024-03-02T10:00:00.000Z',
        'first_watch_at': '2024-03-05T20:00:00.000Z',
        'last_watch_at': '2026-08-20T21:30:00.000Z',
      },
      'badges': [
        {
          'id': 'time-10h',
          'name': 'Regular',
          'description': 'Watched for 10 hours in total.',
          'icon': '⏱️',
          'category': 'time',
          'tier': 2,
          'threshold': 36000,
          'progress': 512345,
          'earned': true,
          'earned_at': '2025-01-04T09:00:00.000Z',
        },
      ],
    });

    expect(stats.stats.totalWatchSeconds, 512345);
    expect(stats.stats.averageRating, 7.6);
    expect(stats.stats.topProvider, 'filmhub');
    expect(stats.stats.memberSince?.year, 2024);
    expect(stats.badges.single.name, 'Regular');
    expect(stats.badges.single.earned, isTrue);
    expect(stats.earned, hasLength(1));
  });

  test('bigints arriving as strings still parse', () {
    final stats = UserStats.fromJson({
      'total_watch_seconds': '512345',
      'episodes_completed': '210',
    });

    expect(stats.totalWatchSeconds, 512345);
    expect(stats.episodesCompleted, 210);
  });

  test('missing numbers default to zero and absent dates stay null', () {
    final stats = UserStats.fromJson(const {});

    expect(stats.totalWatchSeconds, 0);
    expect(stats.favoritesCount, 0);
    expect(stats.averageRating, isNull);
    expect(stats.topProvider, isNull);
    expect(stats.memberSince, isNull);
  });

  test('an empty top_provider reads as none rather than a blank name', () {
    expect(UserStats.fromJson(const {'top_provider': ''}).topProvider, isNull);
  });

  test('an unearned badge reports its progress as a fraction', () {
    final badge = BadgeStatus.fromJson(const {
      'id': 'eps-100',
      'name': 'Binger',
      'description': 'Finished 100 episodes.',
      'icon': '📺',
      'category': 'episodes',
      'tier': 3,
      'threshold': 100,
      'progress': 25,
      'earned': false,
      'earned_at': null,
    });

    expect(badge.earned, isFalse);
    expect(badge.earnedAt, isNull);
    expect(badge.fraction, 0.25);
  });

  test('an earned badge is always full, even if the stat fell back', () {
    final badge = BadgeStatus.fromJson(const {
      'id': 'social-1',
      'threshold': 10,
      'progress': 2,
      'earned': true,
    });

    expect(badge.fraction, 1);
  });

  test('a zero threshold does not divide by zero', () {
    expect(
        BadgeStatus.fromJson(const {'id': 'x', 'threshold': 0, 'progress': 5})
            .fraction,
        0);
  });

  test('a category this build has never heard of still parses', () {
    // The catalogue is the server's, and a new category must not break the
    // grid — which is why `category` is a bare String and not an enum.
    expect(BadgeStatus.fromJson(const {'id': 'x', 'category': 'holidays'}).category,
        'holidays');
  });

  test('a malformed envelope yields empty rather than throwing', () {
    final stats = AccountStats.fromJson(const {'stats': null, 'badges': null});

    expect(stats.badges, isEmpty);
    expect(stats.stats.totalWatchSeconds, 0);
  });
}
