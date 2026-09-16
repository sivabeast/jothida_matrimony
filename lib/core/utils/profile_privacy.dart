/// **Server-side field privacy** — how the four Privacy Settings switches are
/// enforced by the database instead of only by the UI.
///
/// Firestore security rules protect whole DOCUMENTS, never single fields. Every
/// signed-in member can read an approved `profiles/{id}` document, so a value
/// stored on it is readable through the SDK no matter what the screen draws —
/// hiding it in a widget is not privacy. The same holds for a phone number on
/// `contacts/{uid}` once contact sharing is open.
///
/// So a hidden value must physically live somewhere the viewer cannot read:
///
///   * `profile_private/{uid}` — the ORIGINAL photo, salary and horoscope,
///     always. Owner, admins and staff only.
///   * `contact_private/{uid}` — the ORIGINAL mobile / WhatsApp numbers,
///     always. Owner and admins only.
///   * `profiles/{id}` and `contacts/{uid}` carry each of those fields only
///     while its switch is OFF; while it is ON they carry a blank.
///
/// Nothing is ever deleted: the private copy is written FIRST, and a public
/// field is blanked only once its value is safely stored there. Turning a
/// switch off copies the value back. The privacy settings themselves are never
/// modified by any of this.
///
/// Owners and admins read the public document with the private copy laid over
/// it ([mergePrivateProfileData] / [mergePrivateContactData]); everybody else
/// reads only what the rules let them, which is exactly what they may see.
///
/// Everything here is pure (maps in, maps out) so the rules of the projection
/// are unit-tested without Firestore.
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../../models/profile_model.dart' show ProfilePrivacy;

/// The profile fields a privacy switch can hide.
class HiddenProfileField {
  HiddenProfileField._();

  /// Hidden by "Hide Profile Photo".
  static const String photo = 'profilePhotoUrl';

  /// Legacy photo arrays that can still carry an image URL on older documents.
  /// They are blanked together with [photo] so a hidden photo cannot be read
  /// back out of them.
  static const List<String> legacyPhotoLists = ['photos', 'additionalPhotos'];

  /// Hidden by "Hide Salary".
  static const String salary = 'annualIncome';

  /// Hidden by "Hide Horoscope Details" — the whole horoscope map, uploaded
  /// horoscope images and PDFs included.
  static const String horoscope = 'horoscope';

  /// The fields kept in `profile_private/{uid}`.
  static const List<String> privateKeys = [photo, salary, horoscope];

  /// The contact fields hidden by "Hide Phone Number" and kept in
  /// `contact_private/{uid}`.
  static const List<String> phoneKeys = ['mobileNumber', 'whatsappNumber'];
}

String _top(String fieldPath) => fieldPath.split('.').first;

/// True when a profile write touches a hideable field, a legacy photo array or
/// the privacy switches — i.e. when it has to go through [splitProfileWrite].
bool touchesPrivateProfileFields(Map<String, dynamic> data) => data.keys.any(
      (k) {
        final top = _top(k);
        return HiddenProfileField.privateKeys.contains(top) ||
            HiddenProfileField.legacyPhotoLists.contains(top) ||
            top == 'privacySettings';
      },
    );

/// A profile write split into its member-readable and private halves.
typedef ProfileWriteSplit = ({
  Map<String, dynamic> public,
  Map<String, dynamic> private,
});

/// Splits a profile write ([data], using Firestore field paths such as
/// `horoscope.birthTime`) according to [privacy].
///
///  * A hideable field ALWAYS goes to the private half, with its real value.
///  * It goes to the public half with its real value while its switch is off,
///    and as a blank while it is on. A dotted horoscope write while the
///    horoscope is hidden blanks the whole public map, so an old unredacted
///    horoscope can never survive next to a new private one.
///  * Everything else is public only.
ProfileWriteSplit splitProfileWrite(
  Map<String, dynamic> data,
  Map<String, bool> privacy,
) {
  final hidePhoto = ProfilePrivacy.isHidden(privacy, ProfilePrivacy.photo);
  final hideSalary = ProfilePrivacy.isHidden(privacy, ProfilePrivacy.salary);
  final hideHoroscope =
      ProfilePrivacy.isHidden(privacy, ProfilePrivacy.horoscope);

  final public = <String, dynamic>{};
  final private = <String, dynamic>{};

  for (final entry in data.entries) {
    final key = entry.key;
    final value = entry.value;
    final top = _top(key);

    if (top == HiddenProfileField.photo) {
      private[key] = value;
      public[key] = hidePhoto ? null : value;
      if (hidePhoto) {
        for (final list in HiddenProfileField.legacyPhotoLists) {
          public[list] = const <String>[];
        }
      }
    } else if (HiddenProfileField.legacyPhotoLists.contains(top)) {
      public[key] = hidePhoto ? const <String>[] : value;
    } else if (top == HiddenProfileField.salary) {
      private[key] = value;
      public[key] = hideSalary ? '' : value;
    } else if (top == HiddenProfileField.horoscope) {
      private[key] = value;
      if (!hideHoroscope) {
        public[key] = value;
      } else {
        public[HiddenProfileField.horoscope] = const <String, dynamic>{};
      }
    } else {
      public[key] = value;
    }
  }
  return (public: public, private: private);
}

/// The public values of every hideable field for [truth] (the full, unredacted
/// profile data) under [privacy] — what `profiles/{id}` must carry after the
/// switches change.
Map<String, dynamic> projectPublicPrivateFields(
  Map<String, dynamic> truth,
  Map<String, bool> privacy,
) {
  final hidePhoto = ProfilePrivacy.isHidden(privacy, ProfilePrivacy.photo);
  final hideSalary = ProfilePrivacy.isHidden(privacy, ProfilePrivacy.salary);
  final hideHoroscope =
      ProfilePrivacy.isHidden(privacy, ProfilePrivacy.horoscope);
  return {
    HiddenProfileField.photo: hidePhoto ? null : truth[HiddenProfileField.photo],
    if (hidePhoto)
      for (final list in HiddenProfileField.legacyPhotoLists)
        list: const <String>[],
    HiddenProfileField.salary:
        hideSalary ? '' : (truth[HiddenProfileField.salary] ?? ''),
    HiddenProfileField.horoscope: hideHoroscope
        ? const <String, dynamic>{}
        : (truth[HiddenProfileField.horoscope] ?? const <String, dynamic>{}),
  };
}

/// The private snapshot of [truth] — what `profile_private/{uid}` must carry.
Map<String, dynamic> privateSnapshotOf(Map<String, dynamic> truth) => {
      HiddenProfileField.photo: truth[HiddenProfileField.photo],
      HiddenProfileField.salary: truth[HiddenProfileField.salary] ?? '',
      HiddenProfileField.horoscope:
          truth[HiddenProfileField.horoscope] ?? const <String, dynamic>{},
    };

/// The member's full profile data: [publicData] with the private copy laid
/// over it. Used ONLY for the owner and for admins / staff.
///
/// The private copy is authoritative, with one exception that keeps data from
/// being lost while old app builds are still installed: a build that predates
/// the private copy writes a new value straight onto the public document. When
/// the public document is NEWER than the private copy and holds a real value
/// that differs from it, that public value is the latest one the member saved,
/// so it wins until the next reconcile copies it across.
Map<String, dynamic> mergePrivateProfileData(
  Map<String, dynamic> publicData,
  Map<String, dynamic>? privateData,
) {
  if (privateData == null || privateData.isEmpty) return publicData;
  return _overlay(
    publicData,
    privateData,
    HiddenProfileField.privateKeys,
  );
}

/// [contactData] (`contacts/{uid}`) with the private phone numbers laid over
/// it — owner and admin reads only. Same precedence rule as
/// [mergePrivateProfileData].
Map<String, dynamic> mergePrivateContactData(
  Map<String, dynamic> contactData,
  Map<String, dynamic>? privateData,
) {
  if (privateData == null || privateData.isEmpty) return contactData;
  return _overlay(contactData, privateData, HiddenProfileField.phoneKeys);
}

Map<String, dynamic> _overlay(
  Map<String, dynamic> publicData,
  Map<String, dynamic> privateData,
  List<String> keys,
) {
  final out = Map<String, dynamic>.of(publicData);
  final publicAt = _millis(publicData['updatedAt']);
  final privateAt = _millis(privateData['updatedAt']);
  for (final key in keys) {
    if (!privateData.containsKey(key)) continue;
    final pub = publicData[key];
    final priv = privateData[key];
    final publicIsNewer =
        publicAt != null && privateAt != null && publicAt > privateAt;
    if (publicIsNewer && hasStoredValue(pub) && !_deepEquals(pub, priv)) {
      continue; // written by a client unaware of the private copy
    }
    out[key] = priv;
  }
  return out;
}

/// A contact write split into what `contacts/{uid}` carries and the phone
/// numbers `contact_private/{uid}` keeps.
typedef ContactWriteSplit = ({
  Map<String, dynamic> public,
  Map<String, dynamic> private,
});

ContactWriteSplit splitContactWrite(
  Map<String, dynamic> contact, {
  required bool hidePhone,
}) {
  final public = Map<String, dynamic>.of(contact);
  final private = <String, dynamic>{};
  for (final key in HiddenProfileField.phoneKeys) {
    if (!contact.containsKey(key)) continue;
    private[key] = contact[key] ?? '';
    if (hidePhone) public[key] = '';
  }
  return (public: public, private: private);
}

/// True when [value] is something worth keeping — not null, not blank, not an
/// empty list or map.
bool hasStoredValue(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  return true;
}

/// [truth] with the write [data] applied, honouring Firestore field paths
/// (`horoscope.birthTime` replaces one key inside the horoscope map, a plain
/// `horoscope` replaces the whole map) — the same semantics `update()` has.
/// Nested maps are copied, never mutated in place.
Map<String, dynamic> applyProfileWrite(
  Map<String, dynamic> truth,
  Map<String, dynamic> data,
) {
  final out = _deepCopyMap(truth);
  for (final entry in data.entries) {
    final parts = entry.key.split('.');
    var node = out;
    for (var i = 0; i < parts.length - 1; i++) {
      final next = node[parts[i]];
      final copy = next is Map
          ? _deepCopyMap(Map<String, dynamic>.from(next))
          : <String, dynamic>{};
      node[parts[i]] = copy;
      node = copy;
    }
    node[parts.last] = entry.value;
  }
  return out;
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) => {
      for (final e in source.entries)
        e.key: e.value is Map
            ? _deepCopyMap(Map<String, dynamic>.from(e.value as Map))
            : e.value is List
                ? List<dynamic>.of(e.value as List)
                : e.value,
    };

/// Turns Firestore field paths (`horoscope.birthTime`) into nested maps, which
/// is the shape `set(..., SetOptions(mergeFields: …))` expects.
Map<String, dynamic> nestFieldPaths(Map<String, dynamic> flat) {
  final out = <String, dynamic>{};
  for (final entry in flat.entries) {
    final parts = entry.key.split('.');
    var node = out;
    for (var i = 0; i < parts.length - 1; i++) {
      final next = node[parts[i]];
      if (next is Map<String, dynamic>) {
        node = next;
      } else {
        final created = <String, dynamic>{};
        node[parts[i]] = created;
        node = created;
      }
    }
    node[parts.last] = entry.value;
  }
  return out;
}

int? _millis(Object? v) {
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is DateTime) return v.millisecondsSinceEpoch;
  return null;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// What the member-readable documents must look like for a member, compared
/// with what they are — the plan [FirestoreService.reconcileMemberPrivacy]
/// executes. Pure, so "which writes does this member need" is testable.
class PrivacyReconcilePlan {
  /// Full private snapshot to store, or null when the stored one is current.
  final Map<String, dynamic>? privateWrite;

  /// Fields to update on `profiles/{id}`, or empty when nothing differs.
  final Map<String, dynamic> publicUpdate;

  /// A photo recovered from a legacy array that `profilePhotoUrl` never
  /// received (see `legacyProfilePhoto`), or ''.
  final String recoveredPhoto;

  const PrivacyReconcilePlan({
    required this.privateWrite,
    required this.publicUpdate,
    this.recoveredPhoto = '',
  });

  bool get isNoop => privateWrite == null && publicUpdate.isEmpty;
}

/// Builds the [PrivacyReconcilePlan] for one member.
///
/// [publicData] / [privateData] are the stored documents (the private one may
/// be absent for a member who predates it); [recoveredPhoto] is a legacy photo
/// URL to adopt when the profile has none.
PrivacyReconcilePlan planPrivacyReconcile({
  required Map<String, dynamic> publicData,
  required Map<String, dynamic>? privateData,
  String recoveredPhoto = '',
}) {
  final privacy = ProfilePrivacy.fromMap(publicData['privacySettings']);
  // A COPY: the merge hands back [publicData] itself when there is no private
  // copy, and adopting a recovered photo must not rewrite the "current" values
  // it is compared against below.
  final truth =
      Map<String, dynamic>.of(mergePrivateProfileData(publicData, privateData));
  var adopted = '';
  if (!hasStoredValue(truth[HiddenProfileField.photo]) &&
      recoveredPhoto.trim().isNotEmpty) {
    truth[HiddenProfileField.photo] = recoveredPhoto.trim();
    adopted = recoveredPhoto.trim();
  }

  final snapshot = privateSnapshotOf(truth);
  final storedSnapshot =
      privateData == null ? null : privateSnapshotOf(privateData);
  final privateCurrent = storedSnapshot != null &&
      HiddenProfileField.privateKeys.every((k) =>
          privateData!.containsKey(k) &&
          _deepEquals(storedSnapshot[k], snapshot[k]));

  final projected = projectPublicPrivateFields(truth, privacy);
  final publicUpdate = <String, dynamic>{};
  for (final entry in projected.entries) {
    final current = publicData[entry.key];
    final wanted = entry.value;
    // A missing field, null, '', [] and {} are all "blank" — none of them
    // leaks anything, so converting one into another is not worth a write.
    final same = _deepEquals(current, wanted) ||
        (!hasStoredValue(current) && !hasStoredValue(wanted));
    if (!same) publicUpdate[entry.key] = wanted;
  }
  // Contact details that pre-date the gated `contacts/{uid}` record were
  // embedded in the public profile — phone numbers readable by every member.
  // The contact dialog falls back to them only when `contacts/{uid}` is empty,
  // which the reconcile fills first, so they are removed here.
  if (hasStoredValue(publicData['contact'])) {
    publicUpdate['contact'] = const <String, dynamic>{};
  }

  return PrivacyReconcilePlan(
    privateWrite: privateCurrent ? null : snapshot,
    publicUpdate: publicUpdate,
    recoveredPhoto: adopted,
  );
}
