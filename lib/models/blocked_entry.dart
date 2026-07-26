/// One entry in the signed-in user's Blocked Users list — the blocked user's
/// UID plus when the block was created. Used by the user-facing Blocked Users
/// page (the hide logic elsewhere only needs the id set).
class BlockedEntry {
  final String uid;
  final DateTime? blockedAt;

  const BlockedEntry({required this.uid, this.blockedAt});
}
