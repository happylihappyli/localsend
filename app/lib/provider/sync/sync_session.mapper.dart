// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'sync_session.dart';

class ConflictEntryMapper extends ClassMapperBase<ConflictEntry> {
  ConflictEntryMapper._();

  static ConflictEntryMapper? _instance;
  static ConflictEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ConflictEntryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ConflictEntry';

  static String _$path(ConflictEntry v) => v.path;
  static const Field<ConflictEntry, String> _f$path = Field('path', _$path);
  static String _$localSha256(ConflictEntry v) => v.localSha256;
  static const Field<ConflictEntry, String> _f$localSha256 = Field(
    'localSha256',
    _$localSha256,
  );
  static int _$localSize(ConflictEntry v) => v.localSize;
  static const Field<ConflictEntry, int> _f$localSize = Field(
    'localSize',
    _$localSize,
  );
  static int _$localMtimeUnix(ConflictEntry v) => v.localMtimeUnix;
  static const Field<ConflictEntry, int> _f$localMtimeUnix = Field(
    'localMtimeUnix',
    _$localMtimeUnix,
  );
  static String _$remoteSha256(ConflictEntry v) => v.remoteSha256;
  static const Field<ConflictEntry, String> _f$remoteSha256 = Field(
    'remoteSha256',
    _$remoteSha256,
  );
  static int _$remoteSize(ConflictEntry v) => v.remoteSize;
  static const Field<ConflictEntry, int> _f$remoteSize = Field(
    'remoteSize',
    _$remoteSize,
  );
  static int _$remoteMtimeUnix(ConflictEntry v) => v.remoteMtimeUnix;
  static const Field<ConflictEntry, int> _f$remoteMtimeUnix = Field(
    'remoteMtimeUnix',
    _$remoteMtimeUnix,
  );

  @override
  final MappableFields<ConflictEntry> fields = const {
    #path: _f$path,
    #localSha256: _f$localSha256,
    #localSize: _f$localSize,
    #localMtimeUnix: _f$localMtimeUnix,
    #remoteSha256: _f$remoteSha256,
    #remoteSize: _f$remoteSize,
    #remoteMtimeUnix: _f$remoteMtimeUnix,
  };

  static ConflictEntry _instantiate(DecodingData data) {
    return ConflictEntry(
      path: data.dec(_f$path),
      localSha256: data.dec(_f$localSha256),
      localSize: data.dec(_f$localSize),
      localMtimeUnix: data.dec(_f$localMtimeUnix),
      remoteSha256: data.dec(_f$remoteSha256),
      remoteSize: data.dec(_f$remoteSize),
      remoteMtimeUnix: data.dec(_f$remoteMtimeUnix),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ConflictEntry fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ConflictEntry>(map);
  }

  static ConflictEntry deserialize(String json) {
    return ensureInitialized().decodeJson<ConflictEntry>(json);
  }
}

mixin ConflictEntryMappable {
  String serialize() {
    return ConflictEntryMapper.ensureInitialized().encodeJson<ConflictEntry>(
      this as ConflictEntry,
    );
  }

  Map<String, dynamic> toJson() {
    return ConflictEntryMapper.ensureInitialized().encodeMap<ConflictEntry>(
      this as ConflictEntry,
    );
  }

  ConflictEntryCopyWith<ConflictEntry, ConflictEntry, ConflictEntry>
  get copyWith => _ConflictEntryCopyWithImpl<ConflictEntry, ConflictEntry>(
    this as ConflictEntry,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return ConflictEntryMapper.ensureInitialized().stringifyValue(
      this as ConflictEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return ConflictEntryMapper.ensureInitialized().equalsValue(
      this as ConflictEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return ConflictEntryMapper.ensureInitialized().hashValue(
      this as ConflictEntry,
    );
  }
}

extension ConflictEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ConflictEntry, $Out> {
  ConflictEntryCopyWith<$R, ConflictEntry, $Out> get $asConflictEntry =>
      $base.as((v, t, t2) => _ConflictEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ConflictEntryCopyWith<$R, $In extends ConflictEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? path,
    String? localSha256,
    int? localSize,
    int? localMtimeUnix,
    String? remoteSha256,
    int? remoteSize,
    int? remoteMtimeUnix,
  });
  ConflictEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ConflictEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ConflictEntry, $Out>
    implements ConflictEntryCopyWith<$R, ConflictEntry, $Out> {
  _ConflictEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ConflictEntry> $mapper =
      ConflictEntryMapper.ensureInitialized();
  @override
  $R call({
    String? path,
    String? localSha256,
    int? localSize,
    int? localMtimeUnix,
    String? remoteSha256,
    int? remoteSize,
    int? remoteMtimeUnix,
  }) => $apply(
    FieldCopyWithData({
      if (path != null) #path: path,
      if (localSha256 != null) #localSha256: localSha256,
      if (localSize != null) #localSize: localSize,
      if (localMtimeUnix != null) #localMtimeUnix: localMtimeUnix,
      if (remoteSha256 != null) #remoteSha256: remoteSha256,
      if (remoteSize != null) #remoteSize: remoteSize,
      if (remoteMtimeUnix != null) #remoteMtimeUnix: remoteMtimeUnix,
    }),
  );
  @override
  ConflictEntry $make(CopyWithData data) => ConflictEntry(
    path: data.get(#path, or: $value.path),
    localSha256: data.get(#localSha256, or: $value.localSha256),
    localSize: data.get(#localSize, or: $value.localSize),
    localMtimeUnix: data.get(#localMtimeUnix, or: $value.localMtimeUnix),
    remoteSha256: data.get(#remoteSha256, or: $value.remoteSha256),
    remoteSize: data.get(#remoteSize, or: $value.remoteSize),
    remoteMtimeUnix: data.get(#remoteMtimeUnix, or: $value.remoteMtimeUnix),
  );

  @override
  ConflictEntryCopyWith<$R2, ConflictEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ConflictEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SyncSummaryMapper extends ClassMapperBase<SyncSummary> {
  SyncSummaryMapper._();

  static SyncSummaryMapper? _instance;
  static SyncSummaryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SyncSummaryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SyncSummary';

  static int _$downloaded(SyncSummary v) => v.downloaded;
  static const Field<SyncSummary, int> _f$downloaded = Field(
    'downloaded',
    _$downloaded,
  );
  static int _$skipped(SyncSummary v) => v.skipped;
  static const Field<SyncSummary, int> _f$skipped = Field('skipped', _$skipped);
  static int _$conflictsResolved(SyncSummary v) => v.conflictsResolved;
  static const Field<SyncSummary, int> _f$conflictsResolved = Field(
    'conflictsResolved',
    _$conflictsResolved,
  );
  static List<String> _$errors(SyncSummary v) => v.errors;
  static const Field<SyncSummary, List<String>> _f$errors = Field(
    'errors',
    _$errors,
  );

  @override
  final MappableFields<SyncSummary> fields = const {
    #downloaded: _f$downloaded,
    #skipped: _f$skipped,
    #conflictsResolved: _f$conflictsResolved,
    #errors: _f$errors,
  };

  static SyncSummary _instantiate(DecodingData data) {
    return SyncSummary(
      downloaded: data.dec(_f$downloaded),
      skipped: data.dec(_f$skipped),
      conflictsResolved: data.dec(_f$conflictsResolved),
      errors: data.dec(_f$errors),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SyncSummary fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SyncSummary>(map);
  }

  static SyncSummary deserialize(String json) {
    return ensureInitialized().decodeJson<SyncSummary>(json);
  }
}

mixin SyncSummaryMappable {
  String serialize() {
    return SyncSummaryMapper.ensureInitialized().encodeJson<SyncSummary>(
      this as SyncSummary,
    );
  }

  Map<String, dynamic> toJson() {
    return SyncSummaryMapper.ensureInitialized().encodeMap<SyncSummary>(
      this as SyncSummary,
    );
  }

  SyncSummaryCopyWith<SyncSummary, SyncSummary, SyncSummary> get copyWith =>
      _SyncSummaryCopyWithImpl<SyncSummary, SyncSummary>(
        this as SyncSummary,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SyncSummaryMapper.ensureInitialized().stringifyValue(
      this as SyncSummary,
    );
  }

  @override
  bool operator ==(Object other) {
    return SyncSummaryMapper.ensureInitialized().equalsValue(
      this as SyncSummary,
      other,
    );
  }

  @override
  int get hashCode {
    return SyncSummaryMapper.ensureInitialized().hashValue(this as SyncSummary);
  }
}

extension SyncSummaryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SyncSummary, $Out> {
  SyncSummaryCopyWith<$R, SyncSummary, $Out> get $asSyncSummary =>
      $base.as((v, t, t2) => _SyncSummaryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SyncSummaryCopyWith<$R, $In extends SyncSummary, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get errors;
  $R call({
    int? downloaded,
    int? skipped,
    int? conflictsResolved,
    List<String>? errors,
  });
  SyncSummaryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SyncSummaryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SyncSummary, $Out>
    implements SyncSummaryCopyWith<$R, SyncSummary, $Out> {
  _SyncSummaryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SyncSummary> $mapper =
      SyncSummaryMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get errors =>
      ListCopyWith(
        $value.errors,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(errors: v),
      );
  @override
  $R call({
    int? downloaded,
    int? skipped,
    int? conflictsResolved,
    List<String>? errors,
  }) => $apply(
    FieldCopyWithData({
      if (downloaded != null) #downloaded: downloaded,
      if (skipped != null) #skipped: skipped,
      if (conflictsResolved != null) #conflictsResolved: conflictsResolved,
      if (errors != null) #errors: errors,
    }),
  );
  @override
  SyncSummary $make(CopyWithData data) => SyncSummary(
    downloaded: data.get(#downloaded, or: $value.downloaded),
    skipped: data.get(#skipped, or: $value.skipped),
    conflictsResolved: data.get(
      #conflictsResolved,
      or: $value.conflictsResolved,
    ),
    errors: data.get(#errors, or: $value.errors),
  );

  @override
  SyncSummaryCopyWith<$R2, SyncSummary, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SyncSummaryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SyncSessionMapper extends ClassMapperBase<SyncSession> {
  SyncSessionMapper._();

  static SyncSessionMapper? _instance;
  static SyncSessionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SyncSessionMapper._());
      ConflictEntryMapper.ensureInitialized();
      SyncSummaryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SyncSession';

  static String _$id(SyncSession v) => v.id;
  static const Field<SyncSession, String> _f$id = Field('id', _$id);
  static String _$peerFingerprint(SyncSession v) => v.peerFingerprint;
  static const Field<SyncSession, String> _f$peerFingerprint = Field(
    'peerFingerprint',
    _$peerFingerprint,
  );
  static String _$shareId(SyncSession v) => v.shareId;
  static const Field<SyncSession, String> _f$shareId = Field(
    'shareId',
    _$shareId,
  );
  static String _$shareName(SyncSession v) => v.shareName;
  static const Field<SyncSession, String> _f$shareName = Field(
    'shareName',
    _$shareName,
  );
  static String _$localRoot(SyncSession v) => v.localRoot;
  static const Field<SyncSession, String> _f$localRoot = Field(
    'localRoot',
    _$localRoot,
  );
  static SyncSessionState _$state(SyncSession v) => v.state;
  static const Field<SyncSession, SyncSessionState> _f$state = Field(
    'state',
    _$state,
  );
  static int _$completedTransfers(SyncSession v) => v.completedTransfers;
  static const Field<SyncSession, int> _f$completedTransfers = Field(
    'completedTransfers',
    _$completedTransfers,
  );
  static int _$totalTransfers(SyncSession v) => v.totalTransfers;
  static const Field<SyncSession, int> _f$totalTransfers = Field(
    'totalTransfers',
    _$totalTransfers,
  );
  static List<ConflictEntry> _$openConflicts(SyncSession v) => v.openConflicts;
  static const Field<SyncSession, List<ConflictEntry>> _f$openConflicts = Field(
    'openConflicts',
    _$openConflicts,
  );
  static String? _$error(SyncSession v) => v.error;
  static const Field<SyncSession, String> _f$error = Field('error', _$error);
  static SyncSummary _$summary(SyncSession v) => v.summary;
  static const Field<SyncSession, SyncSummary> _f$summary = Field(
    'summary',
    _$summary,
  );

  @override
  final MappableFields<SyncSession> fields = const {
    #id: _f$id,
    #peerFingerprint: _f$peerFingerprint,
    #shareId: _f$shareId,
    #shareName: _f$shareName,
    #localRoot: _f$localRoot,
    #state: _f$state,
    #completedTransfers: _f$completedTransfers,
    #totalTransfers: _f$totalTransfers,
    #openConflicts: _f$openConflicts,
    #error: _f$error,
    #summary: _f$summary,
  };

  static SyncSession _instantiate(DecodingData data) {
    return SyncSession(
      id: data.dec(_f$id),
      peerFingerprint: data.dec(_f$peerFingerprint),
      shareId: data.dec(_f$shareId),
      shareName: data.dec(_f$shareName),
      localRoot: data.dec(_f$localRoot),
      state: data.dec(_f$state),
      completedTransfers: data.dec(_f$completedTransfers),
      totalTransfers: data.dec(_f$totalTransfers),
      openConflicts: data.dec(_f$openConflicts),
      error: data.dec(_f$error),
      summary: data.dec(_f$summary),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SyncSession fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SyncSession>(map);
  }

  static SyncSession deserialize(String json) {
    return ensureInitialized().decodeJson<SyncSession>(json);
  }
}

mixin SyncSessionMappable {
  String serialize() {
    return SyncSessionMapper.ensureInitialized().encodeJson<SyncSession>(
      this as SyncSession,
    );
  }

  Map<String, dynamic> toJson() {
    return SyncSessionMapper.ensureInitialized().encodeMap<SyncSession>(
      this as SyncSession,
    );
  }

  SyncSessionCopyWith<SyncSession, SyncSession, SyncSession> get copyWith =>
      _SyncSessionCopyWithImpl<SyncSession, SyncSession>(
        this as SyncSession,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SyncSessionMapper.ensureInitialized().stringifyValue(
      this as SyncSession,
    );
  }

  @override
  bool operator ==(Object other) {
    return SyncSessionMapper.ensureInitialized().equalsValue(
      this as SyncSession,
      other,
    );
  }

  @override
  int get hashCode {
    return SyncSessionMapper.ensureInitialized().hashValue(this as SyncSession);
  }
}

extension SyncSessionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SyncSession, $Out> {
  SyncSessionCopyWith<$R, SyncSession, $Out> get $asSyncSession =>
      $base.as((v, t, t2) => _SyncSessionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SyncSessionCopyWith<$R, $In extends SyncSession, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    ConflictEntry,
    ConflictEntryCopyWith<$R, ConflictEntry, ConflictEntry>
  >
  get openConflicts;
  SyncSummaryCopyWith<$R, SyncSummary, SyncSummary> get summary;
  $R call({
    String? id,
    String? peerFingerprint,
    String? shareId,
    String? shareName,
    String? localRoot,
    SyncSessionState? state,
    int? completedTransfers,
    int? totalTransfers,
    List<ConflictEntry>? openConflicts,
    String? error,
    SyncSummary? summary,
  });
  SyncSessionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SyncSessionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SyncSession, $Out>
    implements SyncSessionCopyWith<$R, SyncSession, $Out> {
  _SyncSessionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SyncSession> $mapper =
      SyncSessionMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    ConflictEntry,
    ConflictEntryCopyWith<$R, ConflictEntry, ConflictEntry>
  >
  get openConflicts => ListCopyWith(
    $value.openConflicts,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(openConflicts: v),
  );
  @override
  SyncSummaryCopyWith<$R, SyncSummary, SyncSummary> get summary =>
      $value.summary.copyWith.$chain((v) => call(summary: v));
  @override
  $R call({
    String? id,
    String? peerFingerprint,
    String? shareId,
    String? shareName,
    String? localRoot,
    SyncSessionState? state,
    int? completedTransfers,
    int? totalTransfers,
    List<ConflictEntry>? openConflicts,
    Object? error = $none,
    SyncSummary? summary,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (peerFingerprint != null) #peerFingerprint: peerFingerprint,
      if (shareId != null) #shareId: shareId,
      if (shareName != null) #shareName: shareName,
      if (localRoot != null) #localRoot: localRoot,
      if (state != null) #state: state,
      if (completedTransfers != null) #completedTransfers: completedTransfers,
      if (totalTransfers != null) #totalTransfers: totalTransfers,
      if (openConflicts != null) #openConflicts: openConflicts,
      if (error != $none) #error: error,
      if (summary != null) #summary: summary,
    }),
  );
  @override
  SyncSession $make(CopyWithData data) => SyncSession(
    id: data.get(#id, or: $value.id),
    peerFingerprint: data.get(#peerFingerprint, or: $value.peerFingerprint),
    shareId: data.get(#shareId, or: $value.shareId),
    shareName: data.get(#shareName, or: $value.shareName),
    localRoot: data.get(#localRoot, or: $value.localRoot),
    state: data.get(#state, or: $value.state),
    completedTransfers: data.get(
      #completedTransfers,
      or: $value.completedTransfers,
    ),
    totalTransfers: data.get(#totalTransfers, or: $value.totalTransfers),
    openConflicts: data.get(#openConflicts, or: $value.openConflicts),
    error: data.get(#error, or: $value.error),
    summary: data.get(#summary, or: $value.summary),
  );

  @override
  SyncSessionCopyWith<$R2, SyncSession, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SyncSessionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

