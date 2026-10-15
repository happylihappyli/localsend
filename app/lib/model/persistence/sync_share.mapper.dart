// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'sync_share.dart';

class SyncShareMapper extends ClassMapperBase<SyncShare> {
  SyncShareMapper._();

  static SyncShareMapper? _instance;
  static SyncShareMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SyncShareMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SyncShare';

  static String _$id(SyncShare v) => v.id;
  static const Field<SyncShare, String> _f$id = Field('id', _$id);
  static String _$name(SyncShare v) => v.name;
  static const Field<SyncShare, String> _f$name = Field('name', _$name);
  static String _$root(SyncShare v) => v.root;
  static const Field<SyncShare, String> _f$root = Field('root', _$root);
  static List<String> _$excludes(SyncShare v) => v.excludes;
  static const Field<SyncShare, List<String>> _f$excludes = Field(
    'excludes',
    _$excludes,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<SyncShare> fields = const {
    #id: _f$id,
    #name: _f$name,
    #root: _f$root,
    #excludes: _f$excludes,
  };

  static SyncShare _instantiate(DecodingData data) {
    return SyncShare(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      root: data.dec(_f$root),
      excludes: data.dec(_f$excludes),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SyncShare fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SyncShare>(map);
  }

  static SyncShare deserialize(String json) {
    return ensureInitialized().decodeJson<SyncShare>(json);
  }
}

mixin SyncShareMappable {
  String serialize() {
    return SyncShareMapper.ensureInitialized().encodeJson<SyncShare>(
      this as SyncShare,
    );
  }

  Map<String, dynamic> toJson() {
    return SyncShareMapper.ensureInitialized().encodeMap<SyncShare>(
      this as SyncShare,
    );
  }

  SyncShareCopyWith<SyncShare, SyncShare, SyncShare> get copyWith =>
      _SyncShareCopyWithImpl<SyncShare, SyncShare>(
        this as SyncShare,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SyncShareMapper.ensureInitialized().stringifyValue(
      this as SyncShare,
    );
  }

  @override
  bool operator ==(Object other) {
    return SyncShareMapper.ensureInitialized().equalsValue(
      this as SyncShare,
      other,
    );
  }

  @override
  int get hashCode {
    return SyncShareMapper.ensureInitialized().hashValue(this as SyncShare);
  }
}

extension SyncShareValueCopy<$R, $Out> on ObjectCopyWith<$R, SyncShare, $Out> {
  SyncShareCopyWith<$R, SyncShare, $Out> get $asSyncShare =>
      $base.as((v, t, t2) => _SyncShareCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SyncShareCopyWith<$R, $In extends SyncShare, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get excludes;
  $R call({String? id, String? name, String? root, List<String>? excludes});
  SyncShareCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SyncShareCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SyncShare, $Out>
    implements SyncShareCopyWith<$R, SyncShare, $Out> {
  _SyncShareCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SyncShare> $mapper =
      SyncShareMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get excludes =>
      ListCopyWith(
        $value.excludes,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(excludes: v),
      );
  @override
  $R call({String? id, String? name, String? root, List<String>? excludes}) =>
      $apply(
        FieldCopyWithData({
          if (id != null) #id: id,
          if (name != null) #name: name,
          if (root != null) #root: root,
          if (excludes != null) #excludes: excludes,
        }),
      );
  @override
  SyncShare $make(CopyWithData data) => SyncShare(
    id: data.get(#id, or: $value.id),
    name: data.get(#name, or: $value.name),
    root: data.get(#root, or: $value.root),
    excludes: data.get(#excludes, or: $value.excludes),
  );

  @override
  SyncShareCopyWith<$R2, SyncShare, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SyncShareCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

