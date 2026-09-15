// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DownloadsTable extends Downloads
    with TableInfo<$DownloadsTable, DownloadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _providerMeta =
      const VerificationMeta('provider');
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
      'provider', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _showIdMeta = const VerificationMeta('showId');
  @override
  late final GeneratedColumn<String> showId = GeneratedColumn<String>(
      'show_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentIdMeta =
      const VerificationMeta('contentId');
  @override
  late final GeneratedColumn<String> contentId = GeneratedColumn<String>(
      'content_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentTypeMeta =
      const VerificationMeta('contentType');
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
      'content_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('episode'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _episodeLabelMeta =
      const VerificationMeta('episodeLabel');
  @override
  late final GeneratedColumn<String> episodeLabel = GeneratedColumn<String>(
      'episode_label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _posterMeta = const VerificationMeta('poster');
  @override
  late final GeneratedColumn<String> poster = GeneratedColumn<String>(
      'poster', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _qualityMeta =
      const VerificationMeta('quality');
  @override
  late final GeneratedColumn<String> quality = GeneratedColumn<String>(
      'quality', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _durationSecondsMeta =
      const VerificationMeta('durationSeconds');
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
      'duration_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  late final GeneratedColumnWithTypeConverter<DownloadStatus, int> status =
      GeneratedColumn<int>('status', aliasedName, false,
              type: DriftSqlType.int, requiredDuringInsert: true)
          .withConverter<DownloadStatus>($DownloadsTable.$converterstatus);
  static const VerificationMeta _bytesDownloadedMeta =
      const VerificationMeta('bytesDownloaded');
  @override
  late final GeneratedColumn<int> bytesDownloaded = GeneratedColumn<int>(
      'bytes_downloaded', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _segmentsTotalMeta =
      const VerificationMeta('segmentsTotal');
  @override
  late final GeneratedColumn<int> segmentsTotal = GeneratedColumn<int>(
      'segments_total', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _segmentsDoneMeta =
      const VerificationMeta('segmentsDone');
  @override
  late final GeneratedColumn<int> segmentsDone = GeneratedColumn<int>(
      'segments_done', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _nonceMeta = const VerificationMeta('nonce');
  @override
  late final GeneratedColumn<String> nonce = GeneratedColumn<String>(
      'nonce', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _errorMessageMeta =
      const VerificationMeta('errorMessage');
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
      'error_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _progressSecondsMeta =
      const VerificationMeta('progressSeconds');
  @override
  late final GeneratedColumn<int> progressSeconds = GeneratedColumn<int>(
      'progress_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _progressSyncedMeta =
      const VerificationMeta('progressSynced');
  @override
  late final GeneratedColumn<bool> progressSynced = GeneratedColumn<bool>(
      'progress_synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("progress_synced" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
      'completed_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        provider,
        showId,
        contentId,
        contentType,
        title,
        episodeLabel,
        poster,
        quality,
        durationSeconds,
        status,
        bytesDownloaded,
        segmentsTotal,
        segmentsDone,
        nonce,
        errorMessage,
        progressSeconds,
        progressSynced,
        createdAt,
        completedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downloads';
  @override
  VerificationContext validateIntegrity(Insertable<DownloadRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(_providerMeta,
          provider.isAcceptableOrUnknown(data['provider']!, _providerMeta));
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('show_id')) {
      context.handle(_showIdMeta,
          showId.isAcceptableOrUnknown(data['show_id']!, _showIdMeta));
    } else if (isInserting) {
      context.missing(_showIdMeta);
    }
    if (data.containsKey('content_id')) {
      context.handle(_contentIdMeta,
          contentId.isAcceptableOrUnknown(data['content_id']!, _contentIdMeta));
    } else if (isInserting) {
      context.missing(_contentIdMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
          _contentTypeMeta,
          contentType.isAcceptableOrUnknown(
              data['content_type']!, _contentTypeMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('episode_label')) {
      context.handle(
          _episodeLabelMeta,
          episodeLabel.isAcceptableOrUnknown(
              data['episode_label']!, _episodeLabelMeta));
    }
    if (data.containsKey('poster')) {
      context.handle(_posterMeta,
          poster.isAcceptableOrUnknown(data['poster']!, _posterMeta));
    }
    if (data.containsKey('quality')) {
      context.handle(_qualityMeta,
          quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta));
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
          _durationSecondsMeta,
          durationSeconds.isAcceptableOrUnknown(
              data['duration_seconds']!, _durationSecondsMeta));
    }
    if (data.containsKey('bytes_downloaded')) {
      context.handle(
          _bytesDownloadedMeta,
          bytesDownloaded.isAcceptableOrUnknown(
              data['bytes_downloaded']!, _bytesDownloadedMeta));
    }
    if (data.containsKey('segments_total')) {
      context.handle(
          _segmentsTotalMeta,
          segmentsTotal.isAcceptableOrUnknown(
              data['segments_total']!, _segmentsTotalMeta));
    }
    if (data.containsKey('segments_done')) {
      context.handle(
          _segmentsDoneMeta,
          segmentsDone.isAcceptableOrUnknown(
              data['segments_done']!, _segmentsDoneMeta));
    }
    if (data.containsKey('nonce')) {
      context.handle(
          _nonceMeta, nonce.isAcceptableOrUnknown(data['nonce']!, _nonceMeta));
    } else if (isInserting) {
      context.missing(_nonceMeta);
    }
    if (data.containsKey('error_message')) {
      context.handle(
          _errorMessageMeta,
          errorMessage.isAcceptableOrUnknown(
              data['error_message']!, _errorMessageMeta));
    }
    if (data.containsKey('progress_seconds')) {
      context.handle(
          _progressSecondsMeta,
          progressSeconds.isAcceptableOrUnknown(
              data['progress_seconds']!, _progressSecondsMeta));
    }
    if (data.containsKey('progress_synced')) {
      context.handle(
          _progressSyncedMeta,
          progressSynced.isAcceptableOrUnknown(
              data['progress_synced']!, _progressSyncedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DownloadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      provider: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}provider'])!,
      showId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}show_id'])!,
      contentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_id'])!,
      contentType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      episodeLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}episode_label']),
      poster: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}poster']),
      quality: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}quality']),
      durationSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_seconds'])!,
      status: $DownloadsTable.$converterstatus.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!),
      bytesDownloaded: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bytes_downloaded'])!,
      segmentsTotal: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}segments_total'])!,
      segmentsDone: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}segments_done'])!,
      nonce: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}nonce'])!,
      errorMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_message']),
      progressSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}progress_seconds'])!,
      progressSynced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}progress_synced'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed_at']),
    );
  }

  @override
  $DownloadsTable createAlias(String alias) {
    return $DownloadsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<DownloadStatus, int, int> $converterstatus =
      const EnumIndexConverter<DownloadStatus>(DownloadStatus.values);
}

class DownloadRow extends DataClass implements Insertable<DownloadRow> {
  final String id;
  final String provider;
  final String showId;
  final String contentId;
  final String contentType;
  final String title;
  final String? episodeLabel;
  final String? poster;
  final String? quality;
  final int durationSeconds;
  final DownloadStatus status;
  final int bytesDownloaded;
  final int segmentsTotal;
  final int segmentsDone;

  /// Hex-encoded per-download CTR nonce (see SegmentStore).
  final String nonce;
  final String? errorMessage;

  /// Locally accumulated playback position, flushed to
  /// `POST /api/account/history` once the server is reachable again.
  final int progressSeconds;
  final bool progressSynced;
  final DateTime createdAt;
  final DateTime? completedAt;
  const DownloadRow(
      {required this.id,
      required this.provider,
      required this.showId,
      required this.contentId,
      required this.contentType,
      required this.title,
      this.episodeLabel,
      this.poster,
      this.quality,
      required this.durationSeconds,
      required this.status,
      required this.bytesDownloaded,
      required this.segmentsTotal,
      required this.segmentsDone,
      required this.nonce,
      this.errorMessage,
      required this.progressSeconds,
      required this.progressSynced,
      required this.createdAt,
      this.completedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['provider'] = Variable<String>(provider);
    map['show_id'] = Variable<String>(showId);
    map['content_id'] = Variable<String>(contentId);
    map['content_type'] = Variable<String>(contentType);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || episodeLabel != null) {
      map['episode_label'] = Variable<String>(episodeLabel);
    }
    if (!nullToAbsent || poster != null) {
      map['poster'] = Variable<String>(poster);
    }
    if (!nullToAbsent || quality != null) {
      map['quality'] = Variable<String>(quality);
    }
    map['duration_seconds'] = Variable<int>(durationSeconds);
    {
      map['status'] =
          Variable<int>($DownloadsTable.$converterstatus.toSql(status));
    }
    map['bytes_downloaded'] = Variable<int>(bytesDownloaded);
    map['segments_total'] = Variable<int>(segmentsTotal);
    map['segments_done'] = Variable<int>(segmentsDone);
    map['nonce'] = Variable<String>(nonce);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['progress_seconds'] = Variable<int>(progressSeconds);
    map['progress_synced'] = Variable<bool>(progressSynced);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  DownloadsCompanion toCompanion(bool nullToAbsent) {
    return DownloadsCompanion(
      id: Value(id),
      provider: Value(provider),
      showId: Value(showId),
      contentId: Value(contentId),
      contentType: Value(contentType),
      title: Value(title),
      episodeLabel: episodeLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeLabel),
      poster:
          poster == null && nullToAbsent ? const Value.absent() : Value(poster),
      quality: quality == null && nullToAbsent
          ? const Value.absent()
          : Value(quality),
      durationSeconds: Value(durationSeconds),
      status: Value(status),
      bytesDownloaded: Value(bytesDownloaded),
      segmentsTotal: Value(segmentsTotal),
      segmentsDone: Value(segmentsDone),
      nonce: Value(nonce),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      progressSeconds: Value(progressSeconds),
      progressSynced: Value(progressSynced),
      createdAt: Value(createdAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory DownloadRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadRow(
      id: serializer.fromJson<String>(json['id']),
      provider: serializer.fromJson<String>(json['provider']),
      showId: serializer.fromJson<String>(json['showId']),
      contentId: serializer.fromJson<String>(json['contentId']),
      contentType: serializer.fromJson<String>(json['contentType']),
      title: serializer.fromJson<String>(json['title']),
      episodeLabel: serializer.fromJson<String?>(json['episodeLabel']),
      poster: serializer.fromJson<String?>(json['poster']),
      quality: serializer.fromJson<String?>(json['quality']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      status: $DownloadsTable.$converterstatus
          .fromJson(serializer.fromJson<int>(json['status'])),
      bytesDownloaded: serializer.fromJson<int>(json['bytesDownloaded']),
      segmentsTotal: serializer.fromJson<int>(json['segmentsTotal']),
      segmentsDone: serializer.fromJson<int>(json['segmentsDone']),
      nonce: serializer.fromJson<String>(json['nonce']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      progressSeconds: serializer.fromJson<int>(json['progressSeconds']),
      progressSynced: serializer.fromJson<bool>(json['progressSynced']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'provider': serializer.toJson<String>(provider),
      'showId': serializer.toJson<String>(showId),
      'contentId': serializer.toJson<String>(contentId),
      'contentType': serializer.toJson<String>(contentType),
      'title': serializer.toJson<String>(title),
      'episodeLabel': serializer.toJson<String?>(episodeLabel),
      'poster': serializer.toJson<String?>(poster),
      'quality': serializer.toJson<String?>(quality),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'status': serializer
          .toJson<int>($DownloadsTable.$converterstatus.toJson(status)),
      'bytesDownloaded': serializer.toJson<int>(bytesDownloaded),
      'segmentsTotal': serializer.toJson<int>(segmentsTotal),
      'segmentsDone': serializer.toJson<int>(segmentsDone),
      'nonce': serializer.toJson<String>(nonce),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'progressSeconds': serializer.toJson<int>(progressSeconds),
      'progressSynced': serializer.toJson<bool>(progressSynced),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  DownloadRow copyWith(
          {String? id,
          String? provider,
          String? showId,
          String? contentId,
          String? contentType,
          String? title,
          Value<String?> episodeLabel = const Value.absent(),
          Value<String?> poster = const Value.absent(),
          Value<String?> quality = const Value.absent(),
          int? durationSeconds,
          DownloadStatus? status,
          int? bytesDownloaded,
          int? segmentsTotal,
          int? segmentsDone,
          String? nonce,
          Value<String?> errorMessage = const Value.absent(),
          int? progressSeconds,
          bool? progressSynced,
          DateTime? createdAt,
          Value<DateTime?> completedAt = const Value.absent()}) =>
      DownloadRow(
        id: id ?? this.id,
        provider: provider ?? this.provider,
        showId: showId ?? this.showId,
        contentId: contentId ?? this.contentId,
        contentType: contentType ?? this.contentType,
        title: title ?? this.title,
        episodeLabel:
            episodeLabel.present ? episodeLabel.value : this.episodeLabel,
        poster: poster.present ? poster.value : this.poster,
        quality: quality.present ? quality.value : this.quality,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        status: status ?? this.status,
        bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
        segmentsTotal: segmentsTotal ?? this.segmentsTotal,
        segmentsDone: segmentsDone ?? this.segmentsDone,
        nonce: nonce ?? this.nonce,
        errorMessage:
            errorMessage.present ? errorMessage.value : this.errorMessage,
        progressSeconds: progressSeconds ?? this.progressSeconds,
        progressSynced: progressSynced ?? this.progressSynced,
        createdAt: createdAt ?? this.createdAt,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
      );
  DownloadRow copyWithCompanion(DownloadsCompanion data) {
    return DownloadRow(
      id: data.id.present ? data.id.value : this.id,
      provider: data.provider.present ? data.provider.value : this.provider,
      showId: data.showId.present ? data.showId.value : this.showId,
      contentId: data.contentId.present ? data.contentId.value : this.contentId,
      contentType:
          data.contentType.present ? data.contentType.value : this.contentType,
      title: data.title.present ? data.title.value : this.title,
      episodeLabel: data.episodeLabel.present
          ? data.episodeLabel.value
          : this.episodeLabel,
      poster: data.poster.present ? data.poster.value : this.poster,
      quality: data.quality.present ? data.quality.value : this.quality,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      status: data.status.present ? data.status.value : this.status,
      bytesDownloaded: data.bytesDownloaded.present
          ? data.bytesDownloaded.value
          : this.bytesDownloaded,
      segmentsTotal: data.segmentsTotal.present
          ? data.segmentsTotal.value
          : this.segmentsTotal,
      segmentsDone: data.segmentsDone.present
          ? data.segmentsDone.value
          : this.segmentsDone,
      nonce: data.nonce.present ? data.nonce.value : this.nonce,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      progressSeconds: data.progressSeconds.present
          ? data.progressSeconds.value
          : this.progressSeconds,
      progressSynced: data.progressSynced.present
          ? data.progressSynced.value
          : this.progressSynced,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRow(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('showId: $showId, ')
          ..write('contentId: $contentId, ')
          ..write('contentType: $contentType, ')
          ..write('title: $title, ')
          ..write('episodeLabel: $episodeLabel, ')
          ..write('poster: $poster, ')
          ..write('quality: $quality, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('status: $status, ')
          ..write('bytesDownloaded: $bytesDownloaded, ')
          ..write('segmentsTotal: $segmentsTotal, ')
          ..write('segmentsDone: $segmentsDone, ')
          ..write('nonce: $nonce, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('progressSeconds: $progressSeconds, ')
          ..write('progressSynced: $progressSynced, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      provider,
      showId,
      contentId,
      contentType,
      title,
      episodeLabel,
      poster,
      quality,
      durationSeconds,
      status,
      bytesDownloaded,
      segmentsTotal,
      segmentsDone,
      nonce,
      errorMessage,
      progressSeconds,
      progressSynced,
      createdAt,
      completedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadRow &&
          other.id == this.id &&
          other.provider == this.provider &&
          other.showId == this.showId &&
          other.contentId == this.contentId &&
          other.contentType == this.contentType &&
          other.title == this.title &&
          other.episodeLabel == this.episodeLabel &&
          other.poster == this.poster &&
          other.quality == this.quality &&
          other.durationSeconds == this.durationSeconds &&
          other.status == this.status &&
          other.bytesDownloaded == this.bytesDownloaded &&
          other.segmentsTotal == this.segmentsTotal &&
          other.segmentsDone == this.segmentsDone &&
          other.nonce == this.nonce &&
          other.errorMessage == this.errorMessage &&
          other.progressSeconds == this.progressSeconds &&
          other.progressSynced == this.progressSynced &&
          other.createdAt == this.createdAt &&
          other.completedAt == this.completedAt);
}

class DownloadsCompanion extends UpdateCompanion<DownloadRow> {
  final Value<String> id;
  final Value<String> provider;
  final Value<String> showId;
  final Value<String> contentId;
  final Value<String> contentType;
  final Value<String> title;
  final Value<String?> episodeLabel;
  final Value<String?> poster;
  final Value<String?> quality;
  final Value<int> durationSeconds;
  final Value<DownloadStatus> status;
  final Value<int> bytesDownloaded;
  final Value<int> segmentsTotal;
  final Value<int> segmentsDone;
  final Value<String> nonce;
  final Value<String?> errorMessage;
  final Value<int> progressSeconds;
  final Value<bool> progressSynced;
  final Value<DateTime> createdAt;
  final Value<DateTime?> completedAt;
  final Value<int> rowid;
  const DownloadsCompanion({
    this.id = const Value.absent(),
    this.provider = const Value.absent(),
    this.showId = const Value.absent(),
    this.contentId = const Value.absent(),
    this.contentType = const Value.absent(),
    this.title = const Value.absent(),
    this.episodeLabel = const Value.absent(),
    this.poster = const Value.absent(),
    this.quality = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.status = const Value.absent(),
    this.bytesDownloaded = const Value.absent(),
    this.segmentsTotal = const Value.absent(),
    this.segmentsDone = const Value.absent(),
    this.nonce = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.progressSeconds = const Value.absent(),
    this.progressSynced = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadsCompanion.insert({
    required String id,
    required String provider,
    required String showId,
    required String contentId,
    this.contentType = const Value.absent(),
    required String title,
    this.episodeLabel = const Value.absent(),
    this.poster = const Value.absent(),
    this.quality = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    required DownloadStatus status,
    this.bytesDownloaded = const Value.absent(),
    this.segmentsTotal = const Value.absent(),
    this.segmentsDone = const Value.absent(),
    required String nonce,
    this.errorMessage = const Value.absent(),
    this.progressSeconds = const Value.absent(),
    this.progressSynced = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        provider = Value(provider),
        showId = Value(showId),
        contentId = Value(contentId),
        title = Value(title),
        status = Value(status),
        nonce = Value(nonce);
  static Insertable<DownloadRow> custom({
    Expression<String>? id,
    Expression<String>? provider,
    Expression<String>? showId,
    Expression<String>? contentId,
    Expression<String>? contentType,
    Expression<String>? title,
    Expression<String>? episodeLabel,
    Expression<String>? poster,
    Expression<String>? quality,
    Expression<int>? durationSeconds,
    Expression<int>? status,
    Expression<int>? bytesDownloaded,
    Expression<int>? segmentsTotal,
    Expression<int>? segmentsDone,
    Expression<String>? nonce,
    Expression<String>? errorMessage,
    Expression<int>? progressSeconds,
    Expression<bool>? progressSynced,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (provider != null) 'provider': provider,
      if (showId != null) 'show_id': showId,
      if (contentId != null) 'content_id': contentId,
      if (contentType != null) 'content_type': contentType,
      if (title != null) 'title': title,
      if (episodeLabel != null) 'episode_label': episodeLabel,
      if (poster != null) 'poster': poster,
      if (quality != null) 'quality': quality,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (status != null) 'status': status,
      if (bytesDownloaded != null) 'bytes_downloaded': bytesDownloaded,
      if (segmentsTotal != null) 'segments_total': segmentsTotal,
      if (segmentsDone != null) 'segments_done': segmentsDone,
      if (nonce != null) 'nonce': nonce,
      if (errorMessage != null) 'error_message': errorMessage,
      if (progressSeconds != null) 'progress_seconds': progressSeconds,
      if (progressSynced != null) 'progress_synced': progressSynced,
      if (createdAt != null) 'created_at': createdAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadsCompanion copyWith(
      {Value<String>? id,
      Value<String>? provider,
      Value<String>? showId,
      Value<String>? contentId,
      Value<String>? contentType,
      Value<String>? title,
      Value<String?>? episodeLabel,
      Value<String?>? poster,
      Value<String?>? quality,
      Value<int>? durationSeconds,
      Value<DownloadStatus>? status,
      Value<int>? bytesDownloaded,
      Value<int>? segmentsTotal,
      Value<int>? segmentsDone,
      Value<String>? nonce,
      Value<String?>? errorMessage,
      Value<int>? progressSeconds,
      Value<bool>? progressSynced,
      Value<DateTime>? createdAt,
      Value<DateTime?>? completedAt,
      Value<int>? rowid}) {
    return DownloadsCompanion(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      showId: showId ?? this.showId,
      contentId: contentId ?? this.contentId,
      contentType: contentType ?? this.contentType,
      title: title ?? this.title,
      episodeLabel: episodeLabel ?? this.episodeLabel,
      poster: poster ?? this.poster,
      quality: quality ?? this.quality,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      status: status ?? this.status,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      segmentsTotal: segmentsTotal ?? this.segmentsTotal,
      segmentsDone: segmentsDone ?? this.segmentsDone,
      nonce: nonce ?? this.nonce,
      errorMessage: errorMessage ?? this.errorMessage,
      progressSeconds: progressSeconds ?? this.progressSeconds,
      progressSynced: progressSynced ?? this.progressSynced,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (showId.present) {
      map['show_id'] = Variable<String>(showId.value);
    }
    if (contentId.present) {
      map['content_id'] = Variable<String>(contentId.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (episodeLabel.present) {
      map['episode_label'] = Variable<String>(episodeLabel.value);
    }
    if (poster.present) {
      map['poster'] = Variable<String>(poster.value);
    }
    if (quality.present) {
      map['quality'] = Variable<String>(quality.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (status.present) {
      map['status'] =
          Variable<int>($DownloadsTable.$converterstatus.toSql(status.value));
    }
    if (bytesDownloaded.present) {
      map['bytes_downloaded'] = Variable<int>(bytesDownloaded.value);
    }
    if (segmentsTotal.present) {
      map['segments_total'] = Variable<int>(segmentsTotal.value);
    }
    if (segmentsDone.present) {
      map['segments_done'] = Variable<int>(segmentsDone.value);
    }
    if (nonce.present) {
      map['nonce'] = Variable<String>(nonce.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (progressSeconds.present) {
      map['progress_seconds'] = Variable<int>(progressSeconds.value);
    }
    if (progressSynced.present) {
      map['progress_synced'] = Variable<bool>(progressSynced.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadsCompanion(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('showId: $showId, ')
          ..write('contentId: $contentId, ')
          ..write('contentType: $contentType, ')
          ..write('title: $title, ')
          ..write('episodeLabel: $episodeLabel, ')
          ..write('poster: $poster, ')
          ..write('quality: $quality, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('status: $status, ')
          ..write('bytesDownloaded: $bytesDownloaded, ')
          ..write('segmentsTotal: $segmentsTotal, ')
          ..write('segmentsDone: $segmentsDone, ')
          ..write('nonce: $nonce, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('progressSeconds: $progressSeconds, ')
          ..write('progressSynced: $progressSynced, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadSegmentsTable extends DownloadSegments
    with TableInfo<$DownloadSegmentsTable, DownloadSegmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadSegmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _downloadIdMeta =
      const VerificationMeta('downloadId');
  @override
  late final GeneratedColumn<String> downloadId = GeneratedColumn<String>(
      'download_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES downloads (id) ON DELETE CASCADE'));
  @override
  late final GeneratedColumnWithTypeConverter<TrackKind, int> kind =
      GeneratedColumn<int>('kind', aliasedName, false,
              type: DriftSqlType.int, requiredDuringInsert: true)
          .withConverter<TrackKind>($DownloadSegmentsTable.$converterkind);
  static const VerificationMeta _indexMeta = const VerificationMeta('index');
  @override
  late final GeneratedColumn<int> index = GeneratedColumn<int>(
      'index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _sourceUrlMeta =
      const VerificationMeta('sourceUrl');
  @override
  late final GeneratedColumn<String> sourceUrl = GeneratedColumn<String>(
      'source_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileNameMeta =
      const VerificationMeta('fileName');
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
      'file_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _durationSecondsMeta =
      const VerificationMeta('durationSeconds');
  @override
  late final GeneratedColumn<double> durationSeconds = GeneratedColumn<double>(
      'duration_seconds', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _byteLengthMeta =
      const VerificationMeta('byteLength');
  @override
  late final GeneratedColumn<int> byteLength = GeneratedColumn<int>(
      'byte_length', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<bool> done = GeneratedColumn<bool>(
      'done', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("done" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _keyUriMeta = const VerificationMeta('keyUri');
  @override
  late final GeneratedColumn<String> keyUri = GeneratedColumn<String>(
      'key_uri', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _keyIvMeta = const VerificationMeta('keyIv');
  @override
  late final GeneratedColumn<String> keyIv = GeneratedColumn<String>(
      'key_iv', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        downloadId,
        kind,
        index,
        sourceUrl,
        fileName,
        durationSeconds,
        byteLength,
        done,
        keyUri,
        keyIv
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_segments';
  @override
  VerificationContext validateIntegrity(Insertable<DownloadSegmentRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('download_id')) {
      context.handle(
          _downloadIdMeta,
          downloadId.isAcceptableOrUnknown(
              data['download_id']!, _downloadIdMeta));
    } else if (isInserting) {
      context.missing(_downloadIdMeta);
    }
    if (data.containsKey('index')) {
      context.handle(
          _indexMeta, index.isAcceptableOrUnknown(data['index']!, _indexMeta));
    } else if (isInserting) {
      context.missing(_indexMeta);
    }
    if (data.containsKey('source_url')) {
      context.handle(_sourceUrlMeta,
          sourceUrl.isAcceptableOrUnknown(data['source_url']!, _sourceUrlMeta));
    } else if (isInserting) {
      context.missing(_sourceUrlMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(_fileNameMeta,
          fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta));
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
          _durationSecondsMeta,
          durationSeconds.isAcceptableOrUnknown(
              data['duration_seconds']!, _durationSecondsMeta));
    }
    if (data.containsKey('byte_length')) {
      context.handle(
          _byteLengthMeta,
          byteLength.isAcceptableOrUnknown(
              data['byte_length']!, _byteLengthMeta));
    }
    if (data.containsKey('done')) {
      context.handle(
          _doneMeta, done.isAcceptableOrUnknown(data['done']!, _doneMeta));
    }
    if (data.containsKey('key_uri')) {
      context.handle(_keyUriMeta,
          keyUri.isAcceptableOrUnknown(data['key_uri']!, _keyUriMeta));
    }
    if (data.containsKey('key_iv')) {
      context.handle(
          _keyIvMeta, keyIv.isAcceptableOrUnknown(data['key_iv']!, _keyIvMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {downloadId, kind, index};
  @override
  DownloadSegmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadSegmentRow(
      downloadId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}download_id'])!,
      kind: $DownloadSegmentsTable.$converterkind.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}kind'])!),
      index: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}index'])!,
      sourceUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_url'])!,
      fileName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_name'])!,
      durationSeconds: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}duration_seconds'])!,
      byteLength: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}byte_length'])!,
      done: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}done'])!,
      keyUri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key_uri']),
      keyIv: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key_iv']),
    );
  }

  @override
  $DownloadSegmentsTable createAlias(String alias) {
    return $DownloadSegmentsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TrackKind, int, int> $converterkind =
      const EnumIndexConverter<TrackKind>(TrackKind.values);
}

class DownloadSegmentRow extends DataClass
    implements Insertable<DownloadSegmentRow> {
  final String downloadId;
  final TrackKind kind;
  final int index;
  final String sourceUrl;
  final String fileName;
  final double durationSeconds;
  final int byteLength;
  final bool done;

  /// Upstream `#EXT-X-KEY` for this segment, when the source playlist is
  /// AES-128 encrypted. Kept per segment because a playlist can rotate keys
  /// mid-stream. Both are cleared once the segment is stored — by then it has
  /// been decrypted and re-encrypted under our own key.
  final String? keyUri;

  /// Hex-encoded 16-byte IV (explicit `IV=`, or derived from the media
  /// sequence number per RFC 8216 §5.2).
  final String? keyIv;
  const DownloadSegmentRow(
      {required this.downloadId,
      required this.kind,
      required this.index,
      required this.sourceUrl,
      required this.fileName,
      required this.durationSeconds,
      required this.byteLength,
      required this.done,
      this.keyUri,
      this.keyIv});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['download_id'] = Variable<String>(downloadId);
    {
      map['kind'] =
          Variable<int>($DownloadSegmentsTable.$converterkind.toSql(kind));
    }
    map['index'] = Variable<int>(index);
    map['source_url'] = Variable<String>(sourceUrl);
    map['file_name'] = Variable<String>(fileName);
    map['duration_seconds'] = Variable<double>(durationSeconds);
    map['byte_length'] = Variable<int>(byteLength);
    map['done'] = Variable<bool>(done);
    if (!nullToAbsent || keyUri != null) {
      map['key_uri'] = Variable<String>(keyUri);
    }
    if (!nullToAbsent || keyIv != null) {
      map['key_iv'] = Variable<String>(keyIv);
    }
    return map;
  }

  DownloadSegmentsCompanion toCompanion(bool nullToAbsent) {
    return DownloadSegmentsCompanion(
      downloadId: Value(downloadId),
      kind: Value(kind),
      index: Value(index),
      sourceUrl: Value(sourceUrl),
      fileName: Value(fileName),
      durationSeconds: Value(durationSeconds),
      byteLength: Value(byteLength),
      done: Value(done),
      keyUri:
          keyUri == null && nullToAbsent ? const Value.absent() : Value(keyUri),
      keyIv:
          keyIv == null && nullToAbsent ? const Value.absent() : Value(keyIv),
    );
  }

  factory DownloadSegmentRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadSegmentRow(
      downloadId: serializer.fromJson<String>(json['downloadId']),
      kind: $DownloadSegmentsTable.$converterkind
          .fromJson(serializer.fromJson<int>(json['kind'])),
      index: serializer.fromJson<int>(json['index']),
      sourceUrl: serializer.fromJson<String>(json['sourceUrl']),
      fileName: serializer.fromJson<String>(json['fileName']),
      durationSeconds: serializer.fromJson<double>(json['durationSeconds']),
      byteLength: serializer.fromJson<int>(json['byteLength']),
      done: serializer.fromJson<bool>(json['done']),
      keyUri: serializer.fromJson<String?>(json['keyUri']),
      keyIv: serializer.fromJson<String?>(json['keyIv']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'downloadId': serializer.toJson<String>(downloadId),
      'kind': serializer
          .toJson<int>($DownloadSegmentsTable.$converterkind.toJson(kind)),
      'index': serializer.toJson<int>(index),
      'sourceUrl': serializer.toJson<String>(sourceUrl),
      'fileName': serializer.toJson<String>(fileName),
      'durationSeconds': serializer.toJson<double>(durationSeconds),
      'byteLength': serializer.toJson<int>(byteLength),
      'done': serializer.toJson<bool>(done),
      'keyUri': serializer.toJson<String?>(keyUri),
      'keyIv': serializer.toJson<String?>(keyIv),
    };
  }

  DownloadSegmentRow copyWith(
          {String? downloadId,
          TrackKind? kind,
          int? index,
          String? sourceUrl,
          String? fileName,
          double? durationSeconds,
          int? byteLength,
          bool? done,
          Value<String?> keyUri = const Value.absent(),
          Value<String?> keyIv = const Value.absent()}) =>
      DownloadSegmentRow(
        downloadId: downloadId ?? this.downloadId,
        kind: kind ?? this.kind,
        index: index ?? this.index,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        fileName: fileName ?? this.fileName,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        byteLength: byteLength ?? this.byteLength,
        done: done ?? this.done,
        keyUri: keyUri.present ? keyUri.value : this.keyUri,
        keyIv: keyIv.present ? keyIv.value : this.keyIv,
      );
  DownloadSegmentRow copyWithCompanion(DownloadSegmentsCompanion data) {
    return DownloadSegmentRow(
      downloadId:
          data.downloadId.present ? data.downloadId.value : this.downloadId,
      kind: data.kind.present ? data.kind.value : this.kind,
      index: data.index.present ? data.index.value : this.index,
      sourceUrl: data.sourceUrl.present ? data.sourceUrl.value : this.sourceUrl,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      byteLength:
          data.byteLength.present ? data.byteLength.value : this.byteLength,
      done: data.done.present ? data.done.value : this.done,
      keyUri: data.keyUri.present ? data.keyUri.value : this.keyUri,
      keyIv: data.keyIv.present ? data.keyIv.value : this.keyIv,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadSegmentRow(')
          ..write('downloadId: $downloadId, ')
          ..write('kind: $kind, ')
          ..write('index: $index, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('fileName: $fileName, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('byteLength: $byteLength, ')
          ..write('done: $done, ')
          ..write('keyUri: $keyUri, ')
          ..write('keyIv: $keyIv')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(downloadId, kind, index, sourceUrl, fileName,
      durationSeconds, byteLength, done, keyUri, keyIv);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadSegmentRow &&
          other.downloadId == this.downloadId &&
          other.kind == this.kind &&
          other.index == this.index &&
          other.sourceUrl == this.sourceUrl &&
          other.fileName == this.fileName &&
          other.durationSeconds == this.durationSeconds &&
          other.byteLength == this.byteLength &&
          other.done == this.done &&
          other.keyUri == this.keyUri &&
          other.keyIv == this.keyIv);
}

class DownloadSegmentsCompanion extends UpdateCompanion<DownloadSegmentRow> {
  final Value<String> downloadId;
  final Value<TrackKind> kind;
  final Value<int> index;
  final Value<String> sourceUrl;
  final Value<String> fileName;
  final Value<double> durationSeconds;
  final Value<int> byteLength;
  final Value<bool> done;
  final Value<String?> keyUri;
  final Value<String?> keyIv;
  final Value<int> rowid;
  const DownloadSegmentsCompanion({
    this.downloadId = const Value.absent(),
    this.kind = const Value.absent(),
    this.index = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.fileName = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.byteLength = const Value.absent(),
    this.done = const Value.absent(),
    this.keyUri = const Value.absent(),
    this.keyIv = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadSegmentsCompanion.insert({
    required String downloadId,
    required TrackKind kind,
    required int index,
    required String sourceUrl,
    required String fileName,
    this.durationSeconds = const Value.absent(),
    this.byteLength = const Value.absent(),
    this.done = const Value.absent(),
    this.keyUri = const Value.absent(),
    this.keyIv = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : downloadId = Value(downloadId),
        kind = Value(kind),
        index = Value(index),
        sourceUrl = Value(sourceUrl),
        fileName = Value(fileName);
  static Insertable<DownloadSegmentRow> custom({
    Expression<String>? downloadId,
    Expression<int>? kind,
    Expression<int>? index,
    Expression<String>? sourceUrl,
    Expression<String>? fileName,
    Expression<double>? durationSeconds,
    Expression<int>? byteLength,
    Expression<bool>? done,
    Expression<String>? keyUri,
    Expression<String>? keyIv,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (downloadId != null) 'download_id': downloadId,
      if (kind != null) 'kind': kind,
      if (index != null) 'index': index,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (fileName != null) 'file_name': fileName,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (byteLength != null) 'byte_length': byteLength,
      if (done != null) 'done': done,
      if (keyUri != null) 'key_uri': keyUri,
      if (keyIv != null) 'key_iv': keyIv,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadSegmentsCompanion copyWith(
      {Value<String>? downloadId,
      Value<TrackKind>? kind,
      Value<int>? index,
      Value<String>? sourceUrl,
      Value<String>? fileName,
      Value<double>? durationSeconds,
      Value<int>? byteLength,
      Value<bool>? done,
      Value<String?>? keyUri,
      Value<String?>? keyIv,
      Value<int>? rowid}) {
    return DownloadSegmentsCompanion(
      downloadId: downloadId ?? this.downloadId,
      kind: kind ?? this.kind,
      index: index ?? this.index,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      fileName: fileName ?? this.fileName,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      byteLength: byteLength ?? this.byteLength,
      done: done ?? this.done,
      keyUri: keyUri ?? this.keyUri,
      keyIv: keyIv ?? this.keyIv,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (downloadId.present) {
      map['download_id'] = Variable<String>(downloadId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
          $DownloadSegmentsTable.$converterkind.toSql(kind.value));
    }
    if (index.present) {
      map['index'] = Variable<int>(index.value);
    }
    if (sourceUrl.present) {
      map['source_url'] = Variable<String>(sourceUrl.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<double>(durationSeconds.value);
    }
    if (byteLength.present) {
      map['byte_length'] = Variable<int>(byteLength.value);
    }
    if (done.present) {
      map['done'] = Variable<bool>(done.value);
    }
    if (keyUri.present) {
      map['key_uri'] = Variable<String>(keyUri.value);
    }
    if (keyIv.present) {
      map['key_iv'] = Variable<String>(keyIv.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadSegmentsCompanion(')
          ..write('downloadId: $downloadId, ')
          ..write('kind: $kind, ')
          ..write('index: $index, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('fileName: $fileName, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('byteLength: $byteLength, ')
          ..write('done: $done, ')
          ..write('keyUri: $keyUri, ')
          ..write('keyIv: $keyIv, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DownloadsTable downloads = $DownloadsTable(this);
  late final $DownloadSegmentsTable downloadSegments =
      $DownloadSegmentsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [downloads, downloadSegments];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('downloads',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('download_segments', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$DownloadsTableCreateCompanionBuilder = DownloadsCompanion Function({
  required String id,
  required String provider,
  required String showId,
  required String contentId,
  Value<String> contentType,
  required String title,
  Value<String?> episodeLabel,
  Value<String?> poster,
  Value<String?> quality,
  Value<int> durationSeconds,
  required DownloadStatus status,
  Value<int> bytesDownloaded,
  Value<int> segmentsTotal,
  Value<int> segmentsDone,
  required String nonce,
  Value<String?> errorMessage,
  Value<int> progressSeconds,
  Value<bool> progressSynced,
  Value<DateTime> createdAt,
  Value<DateTime?> completedAt,
  Value<int> rowid,
});
typedef $$DownloadsTableUpdateCompanionBuilder = DownloadsCompanion Function({
  Value<String> id,
  Value<String> provider,
  Value<String> showId,
  Value<String> contentId,
  Value<String> contentType,
  Value<String> title,
  Value<String?> episodeLabel,
  Value<String?> poster,
  Value<String?> quality,
  Value<int> durationSeconds,
  Value<DownloadStatus> status,
  Value<int> bytesDownloaded,
  Value<int> segmentsTotal,
  Value<int> segmentsDone,
  Value<String> nonce,
  Value<String?> errorMessage,
  Value<int> progressSeconds,
  Value<bool> progressSynced,
  Value<DateTime> createdAt,
  Value<DateTime?> completedAt,
  Value<int> rowid,
});

final class $$DownloadsTableReferences
    extends BaseReferences<_$AppDatabase, $DownloadsTable, DownloadRow> {
  $$DownloadsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DownloadSegmentsTable, List<DownloadSegmentRow>>
      _downloadSegmentsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.downloadSegments,
              aliasName: 'downloads__id__download_segments__download_id');

  $$DownloadSegmentsTableProcessedTableManager get downloadSegmentsRefs {
    final manager = $$DownloadSegmentsTableTableManager(
            $_db, $_db.downloadSegments)
        .filter((f) => f.downloadId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_downloadSegmentsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$DownloadsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get showId => $composableBuilder(
      column: $table.showId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentId => $composableBuilder(
      column: $table.contentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentType => $composableBuilder(
      column: $table.contentType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get episodeLabel => $composableBuilder(
      column: $table.episodeLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get poster => $composableBuilder(
      column: $table.poster, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get quality => $composableBuilder(
      column: $table.quality, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<DownloadStatus, DownloadStatus, int>
      get status => $composableBuilder(
          column: $table.status,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<int> get bytesDownloaded => $composableBuilder(
      column: $table.bytesDownloaded,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get segmentsTotal => $composableBuilder(
      column: $table.segmentsTotal, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get segmentsDone => $composableBuilder(
      column: $table.segmentsDone, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nonce => $composableBuilder(
      column: $table.nonce, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get progressSeconds => $composableBuilder(
      column: $table.progressSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get progressSynced => $composableBuilder(
      column: $table.progressSynced,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> downloadSegmentsRefs(
      Expression<bool> Function($$DownloadSegmentsTableFilterComposer f) f) {
    final $$DownloadSegmentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadSegments,
        getReferencedColumn: (t) => t.downloadId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadSegmentsTableFilterComposer(
              $db: $db,
              $table: $db.downloadSegments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$DownloadsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get showId => $composableBuilder(
      column: $table.showId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentId => $composableBuilder(
      column: $table.contentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentType => $composableBuilder(
      column: $table.contentType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get episodeLabel => $composableBuilder(
      column: $table.episodeLabel,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get poster => $composableBuilder(
      column: $table.poster, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get quality => $composableBuilder(
      column: $table.quality, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bytesDownloaded => $composableBuilder(
      column: $table.bytesDownloaded,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get segmentsTotal => $composableBuilder(
      column: $table.segmentsTotal,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get segmentsDone => $composableBuilder(
      column: $table.segmentsDone,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nonce => $composableBuilder(
      column: $table.nonce, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get progressSeconds => $composableBuilder(
      column: $table.progressSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get progressSynced => $composableBuilder(
      column: $table.progressSynced,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));
}

class $$DownloadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get showId =>
      $composableBuilder(column: $table.showId, builder: (column) => column);

  GeneratedColumn<String> get contentId =>
      $composableBuilder(column: $table.contentId, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
      column: $table.contentType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get episodeLabel => $composableBuilder(
      column: $table.episodeLabel, builder: (column) => column);

  GeneratedColumn<String> get poster =>
      $composableBuilder(column: $table.poster, builder: (column) => column);

  GeneratedColumn<String> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DownloadStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get bytesDownloaded => $composableBuilder(
      column: $table.bytesDownloaded, builder: (column) => column);

  GeneratedColumn<int> get segmentsTotal => $composableBuilder(
      column: $table.segmentsTotal, builder: (column) => column);

  GeneratedColumn<int> get segmentsDone => $composableBuilder(
      column: $table.segmentsDone, builder: (column) => column);

  GeneratedColumn<String> get nonce =>
      $composableBuilder(column: $table.nonce, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => column);

  GeneratedColumn<int> get progressSeconds => $composableBuilder(
      column: $table.progressSeconds, builder: (column) => column);

  GeneratedColumn<bool> get progressSynced => $composableBuilder(
      column: $table.progressSynced, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  Expression<T> downloadSegmentsRefs<T extends Object>(
      Expression<T> Function($$DownloadSegmentsTableAnnotationComposer a) f) {
    final $$DownloadSegmentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.downloadSegments,
        getReferencedColumn: (t) => t.downloadId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadSegmentsTableAnnotationComposer(
              $db: $db,
              $table: $db.downloadSegments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$DownloadsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DownloadsTable,
    DownloadRow,
    $$DownloadsTableFilterComposer,
    $$DownloadsTableOrderingComposer,
    $$DownloadsTableAnnotationComposer,
    $$DownloadsTableCreateCompanionBuilder,
    $$DownloadsTableUpdateCompanionBuilder,
    (DownloadRow, $$DownloadsTableReferences),
    DownloadRow,
    PrefetchHooks Function({bool downloadSegmentsRefs})> {
  $$DownloadsTableTableManager(_$AppDatabase db, $DownloadsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> provider = const Value.absent(),
            Value<String> showId = const Value.absent(),
            Value<String> contentId = const Value.absent(),
            Value<String> contentType = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> episodeLabel = const Value.absent(),
            Value<String?> poster = const Value.absent(),
            Value<String?> quality = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            Value<DownloadStatus> status = const Value.absent(),
            Value<int> bytesDownloaded = const Value.absent(),
            Value<int> segmentsTotal = const Value.absent(),
            Value<int> segmentsDone = const Value.absent(),
            Value<String> nonce = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<int> progressSeconds = const Value.absent(),
            Value<bool> progressSynced = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> completedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DownloadsCompanion(
            id: id,
            provider: provider,
            showId: showId,
            contentId: contentId,
            contentType: contentType,
            title: title,
            episodeLabel: episodeLabel,
            poster: poster,
            quality: quality,
            durationSeconds: durationSeconds,
            status: status,
            bytesDownloaded: bytesDownloaded,
            segmentsTotal: segmentsTotal,
            segmentsDone: segmentsDone,
            nonce: nonce,
            errorMessage: errorMessage,
            progressSeconds: progressSeconds,
            progressSynced: progressSynced,
            createdAt: createdAt,
            completedAt: completedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String provider,
            required String showId,
            required String contentId,
            Value<String> contentType = const Value.absent(),
            required String title,
            Value<String?> episodeLabel = const Value.absent(),
            Value<String?> poster = const Value.absent(),
            Value<String?> quality = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            required DownloadStatus status,
            Value<int> bytesDownloaded = const Value.absent(),
            Value<int> segmentsTotal = const Value.absent(),
            Value<int> segmentsDone = const Value.absent(),
            required String nonce,
            Value<String?> errorMessage = const Value.absent(),
            Value<int> progressSeconds = const Value.absent(),
            Value<bool> progressSynced = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> completedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DownloadsCompanion.insert(
            id: id,
            provider: provider,
            showId: showId,
            contentId: contentId,
            contentType: contentType,
            title: title,
            episodeLabel: episodeLabel,
            poster: poster,
            quality: quality,
            durationSeconds: durationSeconds,
            status: status,
            bytesDownloaded: bytesDownloaded,
            segmentsTotal: segmentsTotal,
            segmentsDone: segmentsDone,
            nonce: nonce,
            errorMessage: errorMessage,
            progressSeconds: progressSeconds,
            progressSynced: progressSynced,
            createdAt: createdAt,
            completedAt: completedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$DownloadsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({downloadSegmentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (downloadSegmentsRefs) db.downloadSegments
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (downloadSegmentsRefs)
                    await $_getPrefetchedData<DownloadRow, $DownloadsTable,
                            DownloadSegmentRow>(
                        currentTable: table,
                        referencedTable: $$DownloadsTableReferences
                            ._downloadSegmentsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$DownloadsTableReferences(db, table, p0)
                                .downloadSegmentsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.downloadId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$DownloadsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DownloadsTable,
    DownloadRow,
    $$DownloadsTableFilterComposer,
    $$DownloadsTableOrderingComposer,
    $$DownloadsTableAnnotationComposer,
    $$DownloadsTableCreateCompanionBuilder,
    $$DownloadsTableUpdateCompanionBuilder,
    (DownloadRow, $$DownloadsTableReferences),
    DownloadRow,
    PrefetchHooks Function({bool downloadSegmentsRefs})>;
typedef $$DownloadSegmentsTableCreateCompanionBuilder
    = DownloadSegmentsCompanion Function({
  required String downloadId,
  required TrackKind kind,
  required int index,
  required String sourceUrl,
  required String fileName,
  Value<double> durationSeconds,
  Value<int> byteLength,
  Value<bool> done,
  Value<String?> keyUri,
  Value<String?> keyIv,
  Value<int> rowid,
});
typedef $$DownloadSegmentsTableUpdateCompanionBuilder
    = DownloadSegmentsCompanion Function({
  Value<String> downloadId,
  Value<TrackKind> kind,
  Value<int> index,
  Value<String> sourceUrl,
  Value<String> fileName,
  Value<double> durationSeconds,
  Value<int> byteLength,
  Value<bool> done,
  Value<String?> keyUri,
  Value<String?> keyIv,
  Value<int> rowid,
});

final class $$DownloadSegmentsTableReferences extends BaseReferences<
    _$AppDatabase, $DownloadSegmentsTable, DownloadSegmentRow> {
  $$DownloadSegmentsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $DownloadsTable _downloadIdTable(_$AppDatabase db) =>
      db.downloads.createAlias('download_segments__download_id__downloads__id');

  $$DownloadsTableProcessedTableManager get downloadId {
    final $_column = $_itemColumn<String>('download_id')!;

    final manager = $$DownloadsTableTableManager($_db, $_db.downloads)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_downloadIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$DownloadSegmentsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadSegmentsTable> {
  $$DownloadSegmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnWithTypeConverterFilters<TrackKind, TrackKind, int> get kind =>
      $composableBuilder(
          column: $table.kind,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<int> get index => $composableBuilder(
      column: $table.index, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceUrl => $composableBuilder(
      column: $table.sourceUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get byteLength => $composableBuilder(
      column: $table.byteLength, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get done => $composableBuilder(
      column: $table.done, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get keyUri => $composableBuilder(
      column: $table.keyUri, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get keyIv => $composableBuilder(
      column: $table.keyIv, builder: (column) => ColumnFilters(column));

  $$DownloadsTableFilterComposer get downloadId {
    final $$DownloadsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.downloadId,
        referencedTable: $db.downloads,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadsTableFilterComposer(
              $db: $db,
              $table: $db.downloads,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DownloadSegmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadSegmentsTable> {
  $$DownloadSegmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get index => $composableBuilder(
      column: $table.index, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceUrl => $composableBuilder(
      column: $table.sourceUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get byteLength => $composableBuilder(
      column: $table.byteLength, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get done => $composableBuilder(
      column: $table.done, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get keyUri => $composableBuilder(
      column: $table.keyUri, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get keyIv => $composableBuilder(
      column: $table.keyIv, builder: (column) => ColumnOrderings(column));

  $$DownloadsTableOrderingComposer get downloadId {
    final $$DownloadsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.downloadId,
        referencedTable: $db.downloads,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadsTableOrderingComposer(
              $db: $db,
              $table: $db.downloads,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DownloadSegmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadSegmentsTable> {
  $$DownloadSegmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumnWithTypeConverter<TrackKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get index =>
      $composableBuilder(column: $table.index, builder: (column) => column);

  GeneratedColumn<String> get sourceUrl =>
      $composableBuilder(column: $table.sourceUrl, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<double> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds, builder: (column) => column);

  GeneratedColumn<int> get byteLength => $composableBuilder(
      column: $table.byteLength, builder: (column) => column);

  GeneratedColumn<bool> get done =>
      $composableBuilder(column: $table.done, builder: (column) => column);

  GeneratedColumn<String> get keyUri =>
      $composableBuilder(column: $table.keyUri, builder: (column) => column);

  GeneratedColumn<String> get keyIv =>
      $composableBuilder(column: $table.keyIv, builder: (column) => column);

  $$DownloadsTableAnnotationComposer get downloadId {
    final $$DownloadsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.downloadId,
        referencedTable: $db.downloads,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DownloadsTableAnnotationComposer(
              $db: $db,
              $table: $db.downloads,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DownloadSegmentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DownloadSegmentsTable,
    DownloadSegmentRow,
    $$DownloadSegmentsTableFilterComposer,
    $$DownloadSegmentsTableOrderingComposer,
    $$DownloadSegmentsTableAnnotationComposer,
    $$DownloadSegmentsTableCreateCompanionBuilder,
    $$DownloadSegmentsTableUpdateCompanionBuilder,
    (DownloadSegmentRow, $$DownloadSegmentsTableReferences),
    DownloadSegmentRow,
    PrefetchHooks Function({bool downloadId})> {
  $$DownloadSegmentsTableTableManager(
      _$AppDatabase db, $DownloadSegmentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadSegmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadSegmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadSegmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> downloadId = const Value.absent(),
            Value<TrackKind> kind = const Value.absent(),
            Value<int> index = const Value.absent(),
            Value<String> sourceUrl = const Value.absent(),
            Value<String> fileName = const Value.absent(),
            Value<double> durationSeconds = const Value.absent(),
            Value<int> byteLength = const Value.absent(),
            Value<bool> done = const Value.absent(),
            Value<String?> keyUri = const Value.absent(),
            Value<String?> keyIv = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DownloadSegmentsCompanion(
            downloadId: downloadId,
            kind: kind,
            index: index,
            sourceUrl: sourceUrl,
            fileName: fileName,
            durationSeconds: durationSeconds,
            byteLength: byteLength,
            done: done,
            keyUri: keyUri,
            keyIv: keyIv,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String downloadId,
            required TrackKind kind,
            required int index,
            required String sourceUrl,
            required String fileName,
            Value<double> durationSeconds = const Value.absent(),
            Value<int> byteLength = const Value.absent(),
            Value<bool> done = const Value.absent(),
            Value<String?> keyUri = const Value.absent(),
            Value<String?> keyIv = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DownloadSegmentsCompanion.insert(
            downloadId: downloadId,
            kind: kind,
            index: index,
            sourceUrl: sourceUrl,
            fileName: fileName,
            durationSeconds: durationSeconds,
            byteLength: byteLength,
            done: done,
            keyUri: keyUri,
            keyIv: keyIv,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$DownloadSegmentsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({downloadId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (downloadId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.downloadId,
                    referencedTable:
                        $$DownloadSegmentsTableReferences._downloadIdTable(db),
                    referencedColumn: $$DownloadSegmentsTableReferences
                        ._downloadIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$DownloadSegmentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DownloadSegmentsTable,
    DownloadSegmentRow,
    $$DownloadSegmentsTableFilterComposer,
    $$DownloadSegmentsTableOrderingComposer,
    $$DownloadSegmentsTableAnnotationComposer,
    $$DownloadSegmentsTableCreateCompanionBuilder,
    $$DownloadSegmentsTableUpdateCompanionBuilder,
    (DownloadSegmentRow, $$DownloadSegmentsTableReferences),
    DownloadSegmentRow,
    PrefetchHooks Function({bool downloadId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DownloadsTableTableManager get downloads =>
      $$DownloadsTableTableManager(_db, _db.downloads);
  $$DownloadSegmentsTableTableManager get downloadSegments =>
      $$DownloadSegmentsTableTableManager(_db, _db.downloadSegments);
}
