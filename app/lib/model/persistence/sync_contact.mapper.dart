// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'sync_contact.dart';

class SyncContactMapper extends ClassMapperBase<SyncContact> {
  SyncContactMapper._();

  static SyncContactMapper? _instance;
  static SyncContactMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SyncContactMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SyncContact';

  static String _$id(SyncContact v) => v.id;
  static const Field<SyncContact, String> _f$id = Field('id', _$id);
  static String? _$ip(SyncContact v) => v.ip;
  static const Field<SyncContact, String> _f$ip = Field('ip', _$ip, opt: true);
  static int? _$port(SyncContact v) => v.port;
  static const Field<SyncContact, int> _f$port = Field(
    'port',
    _$port,
    opt: true,
  );
  static String _$alias(SyncContact v) => v.alias;
  static const Field<SyncContact, String> _f$alias = Field('alias', _$alias);
  static bool _$customAlias(SyncContact v) => v.customAlias;
  static const Field<SyncContact, bool> _f$customAlias = Field(
    'customAlias',
    _$customAlias,
    opt: true,
    def: false,
  );
  static bool _$trusted(SyncContact v) => v.trusted;
  static const Field<SyncContact, bool> _f$trusted = Field(
    'trusted',
    _$trusted,
    opt: true,
    def: false,
  );
  static int? _$lastSeenUnix(SyncContact v) => v.lastSeenUnix;
  static const Field<SyncContact, int> _f$lastSeenUnix = Field(
    'lastSeenUnix',
    _$lastSeenUnix,
    opt: true,
  );

  @override
  final MappableFields<SyncContact> fields = const {
    #id: _f$id,
    #ip: _f$ip,
    #port: _f$port,
    #alias: _f$alias,
    #customAlias: _f$customAlias,
    #trusted: _f$trusted,
    #lastSeenUnix: _f$lastSeenUnix,
  };

  static SyncContact _instantiate(DecodingData data) {
    return SyncContact(
      id: data.dec(_f$id),
      ip: data.dec(_f$ip),
      port: data.dec(_f$port),
      alias: data.dec(_f$alias),
      customAlias: data.dec(_f$customAlias),
      trusted: data.dec(_f$trusted),
      lastSeenUnix: data.dec(_f$lastSeenUnix),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SyncContact fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SyncContact>(map);
  }

  static SyncContact deserialize(String json) {
    return ensureInitialized().decodeJson<SyncContact>(json);
  }
}

mixin SyncContactMappable {
  String serialize() {
    return SyncContactMapper.ensureInitialized().encodeJson<SyncContact>(
      this as SyncContact,
    );
  }

  Map<String, dynamic> toJson() {
    return SyncContactMapper.ensureInitialized().encodeMap<SyncContact>(
      this as SyncContact,
    );
  }

  SyncContactCopyWith<SyncContact, SyncContact, SyncContact> get copyWith =>
      _SyncContactCopyWithImpl<SyncContact, SyncContact>(
        this as SyncContact,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SyncContactMapper.ensureInitialized().stringifyValue(
      this as SyncContact,
    );
  }

  @override
  bool operator ==(Object other) {
    return SyncContactMapper.ensureInitialized().equalsValue(
      this as SyncContact,
      other,
    );
  }

  @override
  int get hashCode {
    return SyncContactMapper.ensureInitialized().hashValue(this as SyncContact);
  }
}

extension SyncContactValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SyncContact, $Out> {
  SyncContactCopyWith<$R, SyncContact, $Out> get $asSyncContact =>
      $base.as((v, t, t2) => _SyncContactCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SyncContactCopyWith<$R, $In extends SyncContact, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? ip,
    int? port,
    String? alias,
    bool? customAlias,
    bool? trusted,
    int? lastSeenUnix,
  });
  SyncContactCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SyncContactCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SyncContact, $Out>
    implements SyncContactCopyWith<$R, SyncContact, $Out> {
  _SyncContactCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SyncContact> $mapper =
      SyncContactMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    Object? ip = $none,
    Object? port = $none,
    String? alias,
    bool? customAlias,
    bool? trusted,
    Object? lastSeenUnix = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (ip != $none) #ip: ip,
      if (port != $none) #port: port,
      if (alias != null) #alias: alias,
      if (customAlias != null) #customAlias: customAlias,
      if (trusted != null) #trusted: trusted,
      if (lastSeenUnix != $none) #lastSeenUnix: lastSeenUnix,
    }),
  );
  @override
  SyncContact $make(CopyWithData data) => SyncContact(
    id: data.get(#id, or: $value.id),
    ip: data.get(#ip, or: $value.ip),
    port: data.get(#port, or: $value.port),
    alias: data.get(#alias, or: $value.alias),
    customAlias: data.get(#customAlias, or: $value.customAlias),
    trusted: data.get(#trusted, or: $value.trusted),
    lastSeenUnix: data.get(#lastSeenUnix, or: $value.lastSeenUnix),
  );

  @override
  SyncContactCopyWith<$R2, SyncContact, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SyncContactCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

