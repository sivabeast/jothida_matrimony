/**
 * ACCOUNT MANAGEMENT — the trusted backend for everything the app must not do
 * with its own credentials:
 *
 *   adminInspectLogin          what really exists for a mobile / e-mail / uid
 *   adminProvisionLogin        create, restore or re-key a member's login
 *   adminDeleteLogin           delete a Firebase Auth record (data optional)
 *   adminSetTemporaryPassword  admin-assisted recovery
 *   adminListAuthAccounts      Firebase Auth listing for Account Health
 *   resetPasswordWithPhone     OTP-verified self-service recovery
 *
 * Every admin function re-checks the caller's role from Firestore with the
 * Admin SDK — hiding a button in the app is never the security boundary — and
 * App Check is enforced on all of them. Passwords are only ever passed through
 * to Firebase Auth; nothing here stores one, logs one, or writes one to
 * Firestore (a temporary password travels back to the admin in the callable
 * RESPONSE only).
 *
 * All of these need the Blaze plan (Cloud Functions cannot be deployed on
 * Spark). Until then the app detects the missing backend and uses its limited
 * client-side fallbacks — see lib/services/firebase/account_admin_backend.dart.
 *
 * Pure rules live in accountsCore.js (unit-tested with `node --test`).
 */
'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const core = require('./accountsCore');

const CALLABLE = { enforceAppCheck: true };

const db = () => admin.firestore();
const auth = () => admin.auth();
const FieldValue = admin.firestore.FieldValue;

// ── Shared guards ────────────────────────────────────────────────────────────

/** A signed-in, non-anonymous caller whose users/{uid}.role is admin. */
async function requireAdmin(request) {
  const a = request.auth;
  if (!a || a.token?.firebase?.sign_in_provider === 'anonymous') {
    throw new HttpsError('unauthenticated', 'Sign in as an administrator.');
  }
  const snap = await db().collection('users').doc(a.uid).get();
  const role = snap.exists ? String(snap.get('role') || '') : '';
  if (!core.ADMIN_ROLES.includes(role)) {
    console.warn(`[accounts] non-admin ${a.uid} (role=${role || 'none'}) called an admin function`);
    throw new HttpsError('permission-denied', 'Administrator access is required.');
  }
  return { uid: a.uid, role };
}

/** Fixed-window limit stored in `auth_rate_limits/{key}` (server-only). */
async function enforceRateLimit(key, windowMs, max, message) {
  const ref = db().collection('auth_rate_limits').doc(key.replace(/[/]/g, '_'));
  const allowed = await db().runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    const step = core.rateLimitStep(snap.exists ? snap.data() : null, Date.now(), windowMs, max);
    if (step.allowed) txn.set(ref, { ...step.next, updatedAt: FieldValue.serverTimestamp() });
    return step.allowed;
  });
  if (!allowed) throw new HttpsError('resource-exhausted', message);
}

/** A reason code the app branches on, in `details.reason`. */
function fail(code, reason, message, extra = {}) {
  return new HttpsError(code, message, { reason, ...extra });
}

async function authUserOrNull(fn) {
  try {
    return await fn();
  } catch (err) {
    if (err && err.code === 'auth/user-not-found') return null;
    throw err;
  }
}

function authSummary(u) {
  if (!u) return null;
  return {
    uid: u.uid,
    email: u.email || '',
    phoneNumber: u.phoneNumber || '',
    providers: (u.providerData || []).map((p) => p.providerId),
    disabled: !!u.disabled,
    createdAt: u.metadata?.creationTime ? Date.parse(u.metadata.creationTime) : null,
    lastSignInAt: u.metadata?.lastSignInTime ? Date.parse(u.metadata.lastSignInTime) : null,
  };
}

async function profileSummary(uid) {
  const q = await db().collection('profiles').where('userId', '==', uid).get();
  const real = q.docs.filter((d) => d.get('isDummy') !== true);
  const newest = real.sort((a, b) => {
    const ta = a.get('createdAt')?.toMillis?.() || 0;
    const tb = b.get('createdAt')?.toMillis?.() || 0;
    return tb - ta;
  })[0];
  return {
    profileCount: real.length,
    profileId: newest ? newest.id : '',
    profileName: newest ? String(newest.get('fullName') || '') : '',
    profileStatus: newest ? String(newest.get('status') || '') : '',
  };
}

async function accountDetails(uid, authRecord) {
  const [userSnap, tombSnap, profiles] = await Promise.all([
    db().collection('users').doc(uid).get(),
    db().collection('login_tombstones').doc(uid).get(),
    profileSummary(uid),
  ]);
  const u = userSnap.exists ? userSnap.data() : {};
  return {
    uid,
    auth: authSummary(authRecord),
    hasUserDoc: userSnap.exists,
    displayName: String(u.displayName || ''),
    phone: String(u.phone || ''),
    email: String(u.email || ''),
    role: String(u.role || ''),
    authStatus: String(u.authStatus || 'active'),
    tombstoneMode: tombSnap.exists ? String(tombSnap.get('mode') || '') : '',
    ...profiles,
  };
}

/** Everything that exists for a mobile number (and optionally an e-mail / uid). */
async function inspect({ mobile, email, uid }) {
  const uids = new Map(); // uid → auth record (or null)
  let index = null;
  if (mobile) {
    const snap = await db().collection('login_index').doc(mobile).get();
    if (snap.exists) {
      index = { uid: String(snap.get('uid') || ''), authEmail: String(snap.get('authEmail') || '') };
      if (index.uid) uids.set(index.uid, undefined);
    }
    const byPhone = await authUserOrNull(() => auth().getUserByPhoneNumber(`+91${mobile}`));
    if (byPhone) uids.set(byPhone.uid, byPhone);
    const bySynth = await authUserOrNull(() => auth().getUserByEmail(core.phoneAuthEmail(mobile)));
    if (bySynth) uids.set(bySynth.uid, bySynth);
    const forms = [mobile, `+91${mobile}`, `91${mobile}`];
    const users = await db().collection('users').where('phone', 'in', forms).limit(20).get();
    for (const d of users.docs) if (!uids.has(d.id)) uids.set(d.id, undefined);
  }
  for (const e of [email, index && index.authEmail].filter(Boolean)) {
    const byEmail = await authUserOrNull(() => auth().getUserByEmail(e));
    if (byEmail) uids.set(byEmail.uid, byEmail);
  }
  if (uid && !uids.has(uid)) uids.set(uid, undefined);

  const accounts = [];
  for (const [id, record] of uids) {
    const authRecord = record === undefined ? await authUserOrNull(() => auth().getUser(id)) : record;
    accounts.push(await accountDetails(id, authRecord));
  }
  return { mobile: mobile || '', index, accounts };
}

// ── adminInspectLogin ────────────────────────────────────────────────────────

exports.adminInspectLogin = onCall(CALLABLE, async (request) => {
  const caller = await requireAdmin(request);
  await enforceRateLimit(`inspect_${caller.uid}`, 60 * 60 * 1000, 300, 'Too many lookups. Try again later.');
  const mobile = core.localMobile(request.data?.mobile);
  const email = core.normalizeEmail(request.data?.email);
  const uid = String(request.data?.uid || '').trim();
  if (!mobile && !email && !uid) {
    throw new HttpsError('invalid-argument', 'Give a mobile number, e-mail or account id.');
  }
  if (email && !core.isValidEmail(email)) {
    throw new HttpsError('invalid-argument', 'Enter a valid e-mail address.');
  }
  return inspect({ mobile, email, uid });
});

// ── adminProvisionLogin ──────────────────────────────────────────────────────

exports.adminProvisionLogin = onCall(CALLABLE, async (request) => {
  const caller = await requireAdmin(request);
  await enforceRateLimit(`provision_${caller.uid}`, 60 * 60 * 1000, 60, 'Too many logins created. Try again later.');
  const checked = core.validateProvisionInput(request.data);
  if (!checked.ok) throw new HttpsError('invalid-argument', checked.message);
  const v = checked.value;

  // 1. The phone registry: another LIVE account may not hold this number.
  const indexRef = db().collection('login_index').doc(v.mobile);
  const indexSnap = await indexRef.get();
  const indexUid = indexSnap.exists ? String(indexSnap.get('uid') || '') : '';
  if (indexUid && indexUid !== v.targetUid) {
    const holder = await authUserOrNull(() => auth().getUser(indexUid));
    if (holder) {
      throw fail('already-exists', 'phone-number-already-exists',
        'This mobile number already belongs to another login account.',
        { account: await accountDetails(indexUid, holder) });
    }
    // Stale entry (its Auth record is gone) — it is simply replaced below.
  }

  // 2. The sign-in address.
  const byEmail = await authUserOrNull(() => auth().getUserByEmail(v.authEmail));
  if (byEmail && byEmail.uid !== v.targetUid) {
    const details = await accountDetails(byEmail.uid, byEmail);
    const replaceable = core.isReplaceableOrphan({
      requestedUid: v.replaceOrphanUid,
      authUid: byEmail.uid,
      hasUserDoc: details.hasUserDoc,
      userAuthStatus: details.authStatus,
      profileCount: details.profileCount,
      tombstoneMode: details.tombstoneMode,
    });
    if (!replaceable) {
      throw fail('already-exists',
        details.hasUserDoc || details.profileCount > 0 ? 'email-already-in-use' : 'orphan-auth-account',
        details.hasUserDoc || details.profileCount > 0
          ? 'This sign-in address already belongs to another account.'
          : 'An old Firebase login with this address still exists and nothing in the app uses it.',
        { account: details });
    }
    await auth().deleteUser(byEmail.uid);
    await db().collection('login_tombstones').doc(byEmail.uid).set({
      mode: 'deleted', mobile: v.mobile, authEmail: v.authEmail, authDeleted: true,
      at: FieldValue.serverTimestamp(), by: caller.uid, reason: 'replaced-orphan',
    }, { merge: true });
    console.log(`[adminProvisionLogin] orphan Auth ${byEmail.uid} deleted by ${caller.uid}`);
  }

  // 3. Create, restore (same uid) or re-key the Auth record.
  let uid = v.targetUid;
  let created = false;
  let restored = false;
  if (uid) {
    const existing = await authUserOrNull(() => auth().getUser(uid));
    if (existing) {
      const currentEmail = (existing.email || '').toLowerCase();
      if (currentEmail && currentEmail !== v.authEmail) {
        // Never silently change how an existing member signs in (a Google
        // account's address, a real e-mail): the admin must use that address.
        throw fail('failed-precondition', 'email-mismatch',
          `This account already signs in as ${core.isPhoneAuthEmail(currentEmail) ? 'its mobile number' : currentEmail}. Use that e-mail (or leave it empty for a mobile login).`);
      }
      const update = { password: v.password, disabled: false };
      if (!currentEmail) update.email = v.authEmail;
      if (v.displayName) update.displayName = v.displayName;
      await auth().updateUser(uid, update);
      await auth().revokeRefreshTokens(uid);
      restored = true;
    } else {
      await auth().createUser({ uid, email: v.authEmail, password: v.password, displayName: v.displayName || undefined });
      created = true;
      restored = true;
    }
  } else {
    const user = await auth().createUser({ email: v.authEmail, password: v.password, displayName: v.displayName || undefined });
    uid = user.uid;
    created = true;
  }

  // 4. The app's records — atomically. Roll the Auth record back if they fail.
  try {
    const userRef = db().collection('users').doc(uid);
    await db().runTransaction(async (txn) => {
      const userSnap = await txn.get(userRef);
      const current = userSnap.exists ? userSnap.data() : {};
      txn.set(userRef, {
        phone: v.mobile,
        ...(v.email ? { email: v.email } : {}),
        ...(v.displayName ? { displayName: v.displayName } : {}),
        ...(v.gender && !current.gender ? { gender: v.gender } : {}),
        loginProvider: 'password',
        // Never elevate: an existing role is kept, a new account is a member.
        role: current.role || 'user',
        isProfileComplete: userSnap.exists ? current.isProfileComplete === true : v.profileCreated,
        authStatus: FieldValue.delete(),
        mustChangePassword: v.mustChangePassword,
        updatedAt: FieldValue.serverTimestamp(),
        ...(userSnap.exists ? {} : { createdAt: FieldValue.serverTimestamp(), isBlocked: false }),
      }, { merge: true });
      txn.set(indexRef, { authEmail: v.authEmail, uid, updatedAt: FieldValue.serverTimestamp() });
      txn.delete(db().collection('login_tombstones').doc(uid));
    });
    // Any other registry entry that still points at this uid under an OLD number.
    const others = await db().collection('login_index').where('uid', '==', uid).get();
    for (const d of others.docs) if (d.id !== v.mobile) await d.ref.delete();
  } catch (err) {
    if (created && !v.targetUid) {
      await auth().deleteUser(uid).catch((e) => console.error('[adminProvisionLogin] rollback failed', e));
    }
    console.error('[adminProvisionLogin] Firestore write failed', err);
    throw new HttpsError('internal', 'The login was not saved. Nothing was changed — please try again.');
  }

  await db().collection('admin_logs').add({
    adminUid: caller.uid,
    action: restored ? 'login_restored' : 'login_created',
    targetUid: uid,
    details: `mobile ${v.mobile}${v.email ? ' + e-mail' : ''} (via backend)`,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { uid, authEmail: v.authEmail, mobile: v.mobile, email: v.email, created, restored };
});

// ── adminDeleteLogin ─────────────────────────────────────────────────────────

exports.adminDeleteLogin = onCall(CALLABLE, async (request) => {
  const caller = await requireAdmin(request);
  const uid = String(request.data?.uid || '').trim();
  const keepData = request.data?.keepData === true;
  if (!uid) throw new HttpsError('invalid-argument', 'An account id is required.');
  if (uid === caller.uid) {
    throw new HttpsError('failed-precondition', 'You cannot delete your own login.');
  }
  const userSnap = await db().collection('users').doc(uid).get();
  const role = userSnap.exists ? String(userSnap.get('role') || '') : '';
  if (core.ADMIN_ROLES.includes(role)) {
    throw new HttpsError('failed-precondition', 'Administrator logins cannot be deleted here.');
  }

  const record = await authUserOrNull(() => auth().getUser(uid));
  if (record) await auth().deleteUser(uid);

  const index = await db().collection('login_index').where('uid', '==', uid).get();
  const batch = db().batch();
  for (const d of index.docs) batch.delete(d.ref);
  batch.set(db().collection('login_tombstones').doc(uid), {
    mode: keepData ? 'disabled' : 'deleted',
    mobile: index.docs[0]?.id || (userSnap.exists ? String(userSnap.get('phone') || '') : ''),
    authEmail: record?.email || index.docs[0]?.get('authEmail') || '',
    authDeleted: true,
    at: FieldValue.serverTimestamp(),
    by: caller.uid,
  }, { merge: true });
  if (keepData && userSnap.exists) {
    batch.update(userSnap.ref, {
      authStatus: 'deleted',
      loginRemovedAt: FieldValue.serverTimestamp(),
      loginRemovedBy: caller.uid,
    });
  }
  batch.set(db().collection('admin_logs').doc(), {
    adminUid: caller.uid,
    action: keepData ? 'login_deleted' : 'account_login_deleted',
    targetUid: uid,
    details: record ? 'Firebase Auth record deleted' : 'Firebase Auth record was already gone',
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { authDeleted: !!record, indexRemoved: index.size };
});

// ── adminSetTemporaryPassword ────────────────────────────────────────────────

exports.adminSetTemporaryPassword = onCall(CALLABLE, async (request) => {
  const caller = await requireAdmin(request);
  await enforceRateLimit(`temppw_${caller.uid}`, 60 * 60 * 1000, 30, 'Too many password resets. Try again later.');
  const uid = String(request.data?.uid || '').trim();
  const requestId = String(request.data?.requestId || '').trim();
  if (!uid) throw new HttpsError('invalid-argument', 'An account id is required.');
  const record = await authUserOrNull(() => auth().getUser(uid));
  if (!record) {
    throw fail('failed-precondition', 'user-not-found', 'This account has no Firebase login any more.');
  }
  if (!record.email) {
    throw fail('failed-precondition', 'no-password-login',
      'This account signs in with Google only — it has no password to reset.');
  }
  const role = String((await db().collection('users').doc(uid).get()).get('role') || '');
  if (core.ADMIN_ROLES.includes(role)) {
    throw new HttpsError('failed-precondition', 'Administrator passwords cannot be reset here.');
  }

  const temporaryPassword = core.temporaryPassword();
  await auth().updateUser(uid, { password: temporaryPassword });
  // Every existing session of the account ends now.
  await auth().revokeRefreshTokens(uid);

  const batch = db().batch();
  batch.set(db().collection('users').doc(uid), {
    mustChangePassword: true,
    passwordResetAt: FieldValue.serverTimestamp(),
    passwordResetBy: caller.uid,
  }, { merge: true });
  if (requestId) {
    batch.set(db().collection('password_reset_requests').doc(requestId), {
      status: 'resolved',
      resolution: 'temporary-password',
      resolvedBy: caller.uid,
      resolvedAt: FieldValue.serverTimestamp(),
      matchedUid: uid,
    }, { merge: true });
  }
  batch.set(db().collection('admin_logs').doc(), {
    adminUid: caller.uid,
    action: 'temporary_password_set',
    targetUid: uid,
    details: requestId ? `request ${requestId}` : '',
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  // Returned to the admin's device ONLY — never stored anywhere.
  return { temporaryPassword };
});

// ── adminListAuthAccounts ────────────────────────────────────────────────────

exports.adminListAuthAccounts = onCall(CALLABLE, async (request) => {
  const caller = await requireAdmin(request);
  await enforceRateLimit(`listauth_${caller.uid}`, 60 * 60 * 1000, 200, 'Too many scans. Try again later.');
  const pageToken = request.data?.pageToken ? String(request.data.pageToken) : undefined;
  const page = await auth().listUsers(1000, pageToken);
  return {
    accounts: page.users.map(authSummary),
    nextPageToken: page.pageToken || '',
  };
});

// ── resetPasswordWithPhone ───────────────────────────────────────────────────

/**
 * Self-service recovery. The caller proved possession of the SIM with a
 * Firebase Phone Auth OTP; that signs the device into a PHONE identity, not the
 * member's password account, which is why a trusted backend has to set the
 * password.
 *
 * Two calls from the same OTP session:
 *   { mobile, lookupOnly: true }            → which account(s) may be reset
 *   { mobile, newPassword, accountRef? }    → reset (accountRef when several)
 *
 * The session must be fresh (10 minutes), for the same number, and can reset a
 * password only ONCE. A number tied to more than one matrimony profile is never
 * reset — it is flagged for the admin instead.
 */
// Limited-use App Check tokens, consumed on arrival: a captured request
// cannot be replayed against this endpoint.
exports.resetPasswordWithPhone = onCall({ ...CALLABLE, consumeAppCheckToken: true }, async (request) => {
  const a = request.auth;
  const nowSeconds = Math.floor(Date.now() / 1000);
  const mobile = core.localMobile(request.data?.mobile);
  const problem = core.otpSessionProblem(a && a.token, mobile, nowSeconds);
  if (problem === 'unauthenticated') {
    throw fail('unauthenticated', problem, 'Verify the OTP before resetting your password.');
  }
  if (problem === 'otp-expired') {
    throw fail('failed-precondition', problem, 'This verification has expired. Request a new OTP.');
  }
  if (problem) {
    throw fail('permission-denied', problem, 'This reset requires an OTP-verified session for the same number.');
  }
  const authTime = Number(a.token.auth_time);
  const lookupOnly = request.data?.lookupOnly === true;

  await enforceRateLimit(`recovery_lookup_${mobile}`, 60 * 60 * 1000, 20,
    'Too many attempts for this number. Try again in an hour.');

  const found = await inspect({ mobile });
  const candidates = found.accounts.map((acc) => ({
    uid: acc.uid,
    email: acc.auth ? acc.auth.email : '',
    providers: acc.auth ? acc.auth.providers : [],
    hasUserDoc: acc.hasUserDoc && acc.authStatus === 'active' && acc.tombstoneMode === '',
    profileCount: acc.profileCount,
    displayName: acc.profileName || acc.displayName,
  }));
  // Only live accounts — a deleted or disabled login is never reset, and the
  // throwaway OTP identity (no account record) never qualifies.
  const decision = core.recoveryCandidates(
    candidates.filter((c) => c.hasUserDoc),
    a.uid,
  );

  if (decision.status === 'none') {
    throw fail('failed-precondition', 'no-account',
      'No password account is registered for this mobile number.');
  }
  if (decision.status === 'multiple-profiles') {
    // Flag it — never reset an arbitrary account.
    const day = core.dayKey(Date.now());
    await db().collection('password_reset_requests').doc(`${mobile}_${day}_review`).set({
      mobile,
      status: 'pending',
      needsReview: true,
      reason: 'multiple-profiles',
      description: 'OTP recovery refused: this number belongs to more than one matrimony profile.',
      source: 'otp-recovery',
      createdAt: FieldValue.serverTimestamp(),
      dayKey: day,
    }, { merge: true });
    throw fail('failed-precondition', 'multiple-profiles',
      'This number is linked to more than one profile. The administrator has been asked to resolve it.');
  }

  const accounts = decision.accounts.map((acc) => ({
    ref: core.accountRef(acc.uid, a.uid, authTime),
    label: core.maskEmail(acc.email) || 'Mobile number login',
    name: core.maskName(acc.displayName),
    hasProfile: (acc.profileCount || 0) > 0,
  }));
  if (lookupOnly) return { status: decision.status, accounts };

  const passwordProblem = core.passwordProblem(request.data?.newPassword);
  if (passwordProblem) throw new HttpsError('invalid-argument', passwordProblem);
  let target = decision.accounts[0];
  if (decision.status === 'select') {
    const ref = String(request.data?.accountRef || '');
    target = decision.accounts.find((acc) => core.accountRef(acc.uid, a.uid, authTime) === ref);
    if (!target) {
      throw fail('failed-precondition', 'select-account', 'Choose which account to reset.', { accounts });
    }
  }

  await enforceRateLimit(`recovery_reset_${mobile}`, 24 * 60 * 60 * 1000, 5,
    'Too many password resets for this number today. Contact the administrator.');

  // One reset per OTP session — the verification cannot be replayed.
  const sessionRef = db().collection('auth_recovery_sessions').doc(`${a.uid}_${authTime}`);
  await db().runTransaction(async (txn) => {
    const snap = await txn.get(sessionRef);
    if (snap.exists) {
      throw fail('failed-precondition', 'otp-already-used', 'This verification was already used. Request a new OTP.');
    }
    txn.set(sessionRef, { mobile, uid: target.uid, usedAt: FieldValue.serverTimestamp() });
  });

  await auth().updateUser(target.uid, { password: request.data.newPassword });
  await auth().revokeRefreshTokens(target.uid);
  await db().collection('users').doc(target.uid).set({
    mustChangePassword: false,
    passwordResetAt: FieldValue.serverTimestamp(),
    passwordResetVia: 'otp',
  }, { merge: true });
  console.log(`[resetPasswordWithPhone] password reset for uid=${target.uid}`);

  // Dispose of the throwaway OTP identity unless it IS the account.
  if (a.uid !== target.uid) {
    const sessionUser = await db().collection('users').doc(a.uid).get();
    if (!sessionUser.exists) {
      await auth().deleteUser(a.uid).catch((err) =>
        console.warn('[resetPasswordWithPhone] temp phone identity cleanup skipped:', err));
    }
  }
  return { status: 'reset' };
});
